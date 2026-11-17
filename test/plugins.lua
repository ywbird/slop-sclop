-- bundled plugins; runs last because the IME takes over the input keymap
local I = sclop.input

local ime = require('plugins/korean-ime')
ime.setup()

local function typed(keys)
	I:set('', 0)
	sclop:feedkeys(keys)
	return I.text
end

test('ime: two-set typing composes syllables', function()
	ime.set_mode('ko')
	eq(typed('dkssudgktpdy'), '안녕하세요')
	eq(typed('dkssud gktpdy'), '안녕 하세요')
	eq(typed('dlfrdj'), '읽어')
	eq(typed('rkfkdl'), '가라이')
end)

test('ime: backspace takes back one jamo', function()
	eq(typed('rkr'), '각')
	sclop:feedkeys('\127')
	eq(I.text, '가')
	sclop:feedkeys('\127')
	eq(I.text, 'ㄱ')
	sclop:feedkeys('\127')
	eq(I.text, '')
end)

test('ime: moving the cursor ends the syllable', function()
	eq(typed('rk\27[Dr'), 'ㄱ가')
end)

test('ime: status shows the mode, english types letters', function()
	local segs = {}
	sclop.events.emit(sclop.events.STATUS, segs)
	eq(segs[1], '한')
	ime.change_mode()
	eq(typed('hi there'), 'hi there')
	eq(ime.get_mode(), 'en')
end)

require('plugins/question')

atest('question: options picked by number', function(done)
	local saved = sclop.commit
	sclop.commit = function() end
	sclop.tools.question.run({ questions = {
		{ question = 'Color?', options = { { label = 'red' }, { label = 'blue', description = 'calm' } }, multiple = true },
		{ question = 'Why?' },
	} }, function(text)
		sclop.commit = saved
		local ok, err = pcall(eq, text, 'Q: Color?\nA: red, blue\n\nQ: Why?\nA: 그냥')
		done(not ok and err or nil)
	end)
	local lines = {}
	sclop.view.live(lines)
	eq(lines[3], '  2. blue\27[90m — calm\27[0m')
	I:set('1, 2')
	sclop:feedkeys('\r')
	I:set('그냥')
	sclop:feedkeys('\r')
end)

local wf = require('plugins/webfetch')

test('webfetch: html becomes markdown', function()
	local html = [[<!DOCTYPE html><html><head><title>T</title><style>p{color:red}</style></head>
<body><h1>Title &amp; more</h1><p>Hello <b>bold</b> and
  <a href="/x">a link</a>.</p><script>if (a < b) { x() }</script>
<ul><li>one</li><li>two <ol><li>first</li></ol></li></ul>
<pre><code>int main() {
  return 0;
}</code></pre><p>&#xD55C;&#44544; &lt;tag&gt;</p><!-- <p>hidden</p> --></body></html>]]
	eq(wf.markdown(html, 'https://ex.com/a/b'), '# Title & more\n\nHello **bold** and [a link](https://ex.com/x).\n\n'
		.. '- one\n- two\n  1. first\n\n```\nint main() {\n  return 0;\n}\n```\n\n한글 <tag>')
end)
