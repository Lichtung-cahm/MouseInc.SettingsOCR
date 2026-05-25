import json

with open('D:/origin/MouseInc2.10.21/MouseInc/MouseInc.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

for item in data['MatchGlobal']:
    if item.get('Sign') == 'SQUARE 2':
        item['Actions'] = [
            ['Screenshot', 'ToClipboard'],
            ['Internal', 'Delay', '200'],
            ['Execute', 'powershell -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "D:\\ClaudeCode\\scripts\\save-clipboard.ps1"', 'hide|wait'],
            ['Internal', 'Delay', '200'],
            ['SendKeys', 'Ctrl+V']
        ]
        item['Name'] = '截图贴图'
        print('Fixed')
        break

with open('D:/origin/MouseInc2.10.21/MouseInc/MouseInc.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent='\t')
print('Done')
