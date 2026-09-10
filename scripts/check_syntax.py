#!/usr/bin/env python3
"""Deep PowerShell syntax checker - finds parse-time crash causes."""
import re, sys

path = '/home/z/my-project/scripts/WinPostInstall.ps1'
with open(path, 'r', encoding='utf-8-sig') as f:
    lines = f.readlines()

errors = []
warnings = []

# 1. Check for reserved automatic variables being assigned
# PowerShell automatic variables that CANNOT be assigned
reserved_vars = {
    '$$', '$?', '$^', '$_', '$args', '$ConfirmPreference', '$ConsoleFileName',
    '$DebugPreference', '$Error', '$ErrorActionPreference', '$ErrorView',
    '$ExecutionContext', '$false', '$foreach', '$HOME', '$Host', '$input',
    '$InformationPreference', '$LASTEXITCODE', '$Matches', '$MyInvocation',
    '$NestedPromptLevel', '$null', '$PID', '$Profile', '$ProgressPreference',
    '$PSBoundParameters', '$PSCulture', '$PSDefaultParameterValues',
    '$PSEmailServer', '$PSItem', '$PSScriptRoot', '$PSSessionApplicationName',
    '$PSSessionConfigurationName', '$PSSessionOption', '$PSUICulture',
    '$PSVersionTable', '$PWD', '$ShellId', '$StackTrace', '$switch',
    '$this', '$true', '$VerbosePreference', '$WarningPreference', '$WhatIfPreference',
    '$WhoAmI', '$PSCommandPath'
}

for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if stripped.startswith('#'):
        continue
    
    # Check for assignment to reserved variables
    # Pattern: $varname = (with space before =)
    for rv in sorted(reserved_vars, key=len, reverse=True):
        # Check: $var = or $var=
        pattern = re.escape(rv) + r'\s*='
        if re.search(pattern, line):
            # Exclude $null = (common idiom to suppress output)
            if rv == '$null':
                continue
            # Exclude $ErrorActionPreference (can be set)
            if rv in ('$ErrorActionPreference', '$ProgressPreference', '$VerbosePreference', 
                      '$WarningPreference', '$DebugPreference', '$ConfirmPreference',
                      '$InformationPreference', '$WhatIfPreference'):
                continue
            # Check it's not inside a string
            # Simple check: count quotes before the match
            match = re.search(pattern, line)
            before = line[:match.start()]
            dq_count = before.count('"') - before.count('\\"')
            sq_count = before.count("'") 
            if dq_count % 2 == 0 and sq_count % 2 == 0:
                errors.append(f'Line {i}: Cannot assign to reserved variable {rv}: {stripped[:100]}')

# 2. Check for goto/label syntax
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if stripped.startswith('#'):
        continue
    if re.match(r'^:[A-Za-z]', stripped):
        errors.append(f'Line {i}: PowerShell does not support labels with colon: {stripped[:100]}')
    if re.search(r'\bgoto\b', line, re.IGNORECASE):
        # Make sure it's not in a string
        dq = line.count('"') 
        if 'goto' not in stripped.split('"')[0] if '"' in stripped else True:
            errors.append(f'Line {i}: PowerShell does not support goto: {stripped[:100]}')

# 3. Check for backtick at end of line with no continuation
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if stripped.startswith('#'):
        continue
    if stripped.endswith('`'):
        # Check if next line exists and is not empty
        if i < len(lines):
            next_stripped = lines[i].strip()
            if not next_stripped or next_stripped.startswith('#'):
                warnings.append(f'Line {i}: Backtick continuation but next line is empty/comment')

# 4. Check for unbalanced quotes per line
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if stripped.startswith('#') or not stripped:
        continue
    
    # Simple quote balance check (ignoring escaped quotes)
    in_dq = False
    in_sq = False
    in_here = False
    j = 0
    while j < len(line):
        c = line[j]
        if in_here:
            if j > 0 and line[j-1:j+1] == '"@':
                in_here = False
            j += 1
            continue
        if in_dq:
            if c == '`':
                j += 2  # skip escaped char
                continue
            if c == '"':
                in_dq = False
        elif in_sq:
            if c == "'" and j+1 < len(line) and line[j+1] == "'":
                j += 2  # escaped single quote
                continue
            if c == "'":
                in_sq = False
        else:
            if c == '@' and j+1 < len(line) and line[j+1] == '"':
                in_here = True
                j += 2
                continue
            if c == "'":
                in_sq = True
            elif c == '"':
                in_dq = True
        j += 1
    
    # Don't flag here-strings as they span multiple lines
    if not in_here:
        if in_dq:
            # Could be multi-line double quote - check if next lines close it
            found = False
            for k in range(i, min(i+30, len(lines))):
                if '"' in lines[k]:
                    found = True
                    break
            if not found:
                errors.append(f'Line {i}: Unclosed double quote: {stripped[:100]}')
        if in_sq:
            errors.append(f'Line {i}: Unclosed single quote (PowerShell does not support multi-line single quotes): {stripped[:100]}')

# 5. Check for invalid function definitions
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if stripped.startswith('#'):
        continue
    # Check for function without name
    if re.match(r'^function\s*$', stripped):
        errors.append(f'Line {i}: Function keyword with no name')

# 6. Check for empty catch blocks or malformed try/catch
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if stripped == 'catch {' or stripped == 'catch{':
        # Next non-empty line should have something
        for j in range(i, min(i+3, len(lines))):
            next_s = lines[j].strip()
            if next_s and next_s != '}' and not next_s.startswith('#'):
                break
        else:
            warnings.append(f'Line {i}: Possibly empty catch block')

# 7. Check brace balance with proper tracking
brace_stack = []  # stack of (line_num, context)
in_here = False
here_start = 0
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    
    # Track here-strings
    if '@"' in stripped and not in_here:
        in_here = True
        here_start = i
        continue
    if '"@' in stripped and in_here:
        in_here = False
        continue
    if in_here:
        continue
    if stripped.startswith('#'):
        continue
    
    # Remove string contents for brace counting
    cleaned = re.sub(r'"([^"\\]|\\.)*"', '', line)
    cleaned = re.sub(r"'([^'\\]|\\.)*'", '', cleaned)
    
    for c in cleaned:
        if c == '{':
            brace_stack.append(i)
        elif c == '}':
            if brace_stack:
                brace_stack.pop()
            else:
                errors.append(f'Line {i}: Unexpected closing brace (no matching opening brace)')

if brace_stack:
    for bl in brace_stack:
        errors.append(f'Line {bl}: Unclosed opening brace')

# 8. Check for common typos that are parse errors
for i, line in enumerate(lines, 1):
    stripped = line.strip()
    if stripped.startswith('#'):
        continue
    # Check for 'function' inside pipeline (common mistake)
    # Check for missing - before parameter names in cmdlet calls
    # These are runtime errors, not parse errors, so skip

# 9. Check for BOM / encoding issues
with open(path, 'rb') as f:
    raw = f.read(10)
if raw[:3] == b'\xef\xbb\xbf':
    warnings.append('File has UTF-8 BOM (usually fine but can cause issues with some PowerShell versions)')
elif raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
    warnings.append('File has UTF-16 BOM - this WILL cause parse errors in PowerShell')
if b'\x00' in open(path, 'rb').read():
    errors.append('File contains NUL bytes - will cause parse errors')

# 10. Check for Windows-style line endings that might cause issues
with open(path, 'rb') as f:
    content = f.read()
cr_count = content.count(b'\r')
lf_count = content.count(b'\n')
crlf_count = content.count(b'\r\n')
if cr_count > 0 and crlf_count != cr_count:
    errors.append(f'Mixed line endings: {crlf_count} CRLF + {cr_count - crlf_count} bare CR')
elif cr_count == 0:
    # Pure LF - should be fine for PowerShell on Windows too
    pass

# 11. Check that script starts with valid PowerShell
first_nonblank = ''
for i, line in enumerate(lines, 1):
    if line.strip():
        first_nonblank = line.strip()
        break
if first_nonblank and not first_nonblank.startswith('<#') and not first_nonblank.startswith('#') and not first_nonblank.startswith('param') and not first_nonblank.startswith('[Cmdlet'):
    warnings.append(f'First non-blank line is: {first_nonblank[:80]} (expected <# or param)')

print('=' * 60)
print('POWERSHELL PARSE-TIME ERROR CHECK')
print('=' * 60)
print()
if errors:
    print(f'❌ {len(errors)} ERRORS FOUND (will crash PowerShell):')
    for e in errors:
        print(f'   {e}')
else:
    print('✅ No parse-time errors found')

print()
if warnings:
    print(f'⚠️  {len(warnings)} WARNINGS:')
    for w in warnings:
        print(f'   {w}')
else:
    print('✅ No warnings')

print()
print(f'Script: {path}')
print(f'Lines: {len(lines)}')
