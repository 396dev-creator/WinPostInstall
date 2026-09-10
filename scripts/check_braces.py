import re, sys

with open('/home/z/my-project/scripts/WinPostInstall.ps1', 'r', encoding='utf-8-sig') as f:
    lines = f.readlines()

brace = 0
paren = 0
bracket = 0
here_open = False

for i, line in enumerate(lines, 1):
    s = line.rstrip()
    if not s or s.strip().startswith('#'):
        continue
    # here-string open
    if '@"' in s and not here_open:
        here_open = True
        continue
    if '"@' in s and here_open:
        here_open = False
        continue
    if here_open:
        continue
    # Strip string literals
    s2 = re.sub(r'"[^"]*"', 'X', s)
    s2 = re.sub(r"'[^']*'", 'X', s2)
    o = s2.count('{')
    c = s2.count('}')
    brace += o - c
    if brace < 0:
        print(f'LINE {i}: NEGATIVE brace ({brace}) | {s.strip()[:100]}')

print(f'Final brace balance: {brace}')
if brace != 0:
    print(f'ERROR: {abs(brace)} unmatched braces')
else:
    print('OK: Braces balanced')
