# docs/showcase.src.html の {{galton}} などに examples/*.png を埋め込み、docs/showcase.html を作る
import base64, os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
s = open(os.path.join(root, 'docs/showcase.src.html')).read()
for k in ['galton', 'crowd', 'sand', 'explosion']:
    png = open(os.path.join(root, 'examples', k + '.png'), 'rb').read()
    s = s.replace('{{%s}}' % k, 'data:image/png;base64,' + base64.b64encode(png).decode())
open(os.path.join(root, 'docs/showcase.html'), 'w').write(s)
print('docs/showcase.html', len(s))
