import re, sys

path = '/home/z/my-project/scripts/WinPostInstall.ps1'
with open(path, 'r', encoding='utf-8-sig') as f:
    lines = f.readlines()

i = 0
errors = []
line_num = 0

while i < len(lines):
    line = lines[i]
    line_num = i + 1
    stripped = line.strip()
    
    # Skip comment-only lines
    if stripped.startswith('#'):
        i += 1
        continue
    
    # Check for here-string open
    if '@"' in stripped:
        # Find closing "@
        found = False
        for j in range(i+1, len(lines)):
            if lines[j].strip() == '"@':
                found = True
                i = j + 1
                break
        if not found:
            errors.append(f'Line {line_num}: Unclosed here-string (@"")')
        continue
    
    # Check for unclosed single-quoted strings on a single line
    # In PowerShell, single quotes CANNOT have escape sequences (except '' for literal ')
    # So we can just count unescaped single quotes
    in_sq = False
    in_dq = False
    k = 0
    while k < len(line):
        c = line[k]
        if in_sq:
            if c == "'":
                if k+1 < len(line) and line[k+1] == "'":
                    k += 2  # escaped single quote
                    continue
                in_sq = False
        elif in_dq:
            if c == '`':
                k += 2  # backtick escape
                continue
            if c == '"':
                in_dq = False
        else:
            if c == "'":
                in_sq = True
            elif c == '"':
                in_dq = True
        k += 1
    
    if in_sq:
        # Could be a multi-line single quote (PowerShell doesn't support this normally)
        # Check if next line closes it
        errors.append(f'Line {line_num}: Unclosed single quote: {stripped[:120]}')
    if in_dq:
        # Could be multi-line double quote or here-string
        # Check if next lines close it
        found_close = False
        for j in range(i+1, min(i+20, len(lines))):
            if '"' in lines[j]:
                found_close = True
                break
        if not found_close:
            errors.append(f'Line {line_num}: Unclosed double quote: {stripped[:120]}')
    
    i += 1

if errors:
    print(f'Found {len(errors)} potential issues:')
    for e in errors:
        print(f'  {e}')
else:
    print('No obvious quote/string issues found')

# Also check for backtick at end of line (line continuation)
print()
print('--- Checking backtick continuations ---')
for i, line in enumerate(lines, 1):
    s = line.rstrip()
    if s.endswith('`') and not s.strip().startswith('#'):
        # Next line should NOT be empty or comment-only
        if i < len(lines):
            next_s = lines[i].strip()
            if not next_s or next_s.startswith('#'):
                print(f'Line {i}: Backtick continuation but next line is empty/comment')
