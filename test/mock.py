#!/usr/bin/env python3
"""Mock LLM server for manual testing: python3 test/mock.py [port]

Speaks the Anthropic (/v1/messages) and OpenAI (/chat/completions) streaming APIs.
The reply depends on the last user message:
  tool NAME JSON   ask for a tool call, e.g.  tool bash {"command": "ls"}
  think TEXT       stream some thinking first
  slow TEXT        stream slowly (to test interrupting)
  anything else    echo it back
After a tool result, the reply quotes the start of the result.
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def last_user(messages):
    m = messages[-1]
    content = m.get('content')
    if m.get('role') == 'tool':
        return 'result', m.get('content', '')
    if isinstance(content, str):
        return 'text', content
    for b in content:
        if b.get('type') == 'tool_result':
            c = b.get('content')
            return 'result', c if isinstance(c, str) else json.dumps(c)
    return 'text', ' '.join(b.get('text', '') for b in content if b.get('type') == 'text')


def plan(messages):
    kind, text = last_user(messages)
    if kind == 'result':
        return {'text': 'The tool said: ' + text.strip().replace('\n', ' ')[:60]}
    words = text.split(' ', 2)
    if words[0] == 'tool' and len(words) == 3:
        return {'text': 'Calling ' + words[1] + '.', 'tool': (words[1], json.loads(words[2]))}
    if words[0] == 'think':
        return {'thinking': 'Let me think about this.\nIt is simple.', 'text': 'Thought about: ' + text[6:]}
    if words[0] == 'slow':
        return {'text': 'This reply is slow. ' * 20, 'delay': 0.2}
    return {'text': 'You said: ' + text + '\nThat is all.'}


def chunks(s, n=4):
    return [s[i:i + n] for i in range(0, len(s), n)] or ['']


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def send(self, data):
        self.wfile.write(data.encode())
        self.wfile.flush()

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['content-length'])))
        p = plan(body['messages'])
        delay = p.get('delay', 0.02)
        self.send_response(200)
        self.send_header('content-type', 'text/event-stream')
        self.send_header('connection', 'close')
        self.end_headers()
        if self.path.endswith('/messages'):
            self.anthropic(p, delay)
        else:
            self.openai(p, delay)

    def event(self, name, data):
        self.send('event: %s\ndata: %s\n\n' % (name, json.dumps(data)))

    def anthropic(self, p, delay):
        self.event('message_start', {'type': 'message_start', 'message': {'usage': {'input_tokens': 100, 'output_tokens': 1}}})
        i = 0
        if 'thinking' in p:
            self.event('content_block_start', {'type': 'content_block_start', 'index': i, 'content_block': {'type': 'thinking', 'thinking': ''}})
            for c in chunks(p['thinking']):
                time.sleep(delay)
                self.event('content_block_delta', {'type': 'content_block_delta', 'index': i, 'delta': {'type': 'thinking_delta', 'thinking': c}})
            self.event('content_block_delta', {'type': 'content_block_delta', 'index': i, 'delta': {'type': 'signature_delta', 'signature': 'sig'}})
            self.event('content_block_stop', {'type': 'content_block_stop', 'index': i})
            i += 1
        self.event('content_block_start', {'type': 'content_block_start', 'index': i, 'content_block': {'type': 'text', 'text': ''}})
        for c in chunks(p['text']):
            time.sleep(delay)
            self.event('content_block_delta', {'type': 'content_block_delta', 'index': i, 'delta': {'type': 'text_delta', 'text': c}})
        self.event('content_block_stop', {'type': 'content_block_stop', 'index': i})
        if 'tool' in p:
            i += 1
            name, args = p['tool']
            self.event('content_block_start', {'type': 'content_block_start', 'index': i, 'content_block': {'type': 'tool_use', 'id': 'toolu_%d' % time.time_ns(), 'name': name, 'input': {}}})
            for c in chunks(json.dumps(args), 8):
                self.event('content_block_delta', {'type': 'content_block_delta', 'index': i, 'delta': {'type': 'input_json_delta', 'partial_json': c}})
            self.event('content_block_stop', {'type': 'content_block_stop', 'index': i})
        self.event('message_delta', {'type': 'message_delta', 'delta': {'stop_reason': 'tool_use' if 'tool' in p else 'end_turn'}, 'usage': {'output_tokens': 50}})
        self.event('message_stop', {'type': 'message_stop'})

    def openai(self, p, delay):
        def data(d):
            self.send('data: %s\n\n' % json.dumps(d))
        if 'thinking' in p:
            for c in chunks(p['thinking']):
                time.sleep(delay)
                data({'choices': [{'delta': {'reasoning_content': c}}]})
        for c in chunks(p['text']):
            time.sleep(delay)
            data({'choices': [{'delta': {'content': c}}]})
        if 'tool' in p:
            name, args = p['tool']
            data({'choices': [{'delta': {'tool_calls': [{'index': 0, 'id': 'call_%d' % time.time_ns(), 'function': {'name': name, 'arguments': ''}}]}}]})
            for c in chunks(json.dumps(args), 8):
                data({'choices': [{'delta': {'tool_calls': [{'index': 0, 'function': {'arguments': c}}]}}]})
        data({'choices': [{'delta': {}, 'finish_reason': 'tool_calls' if 'tool' in p else 'stop'}]})
        data({'choices': [], 'usage': {'prompt_tokens': 100, 'completion_tokens': 50}})
        self.send('data: [DONE]\n\n')


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
