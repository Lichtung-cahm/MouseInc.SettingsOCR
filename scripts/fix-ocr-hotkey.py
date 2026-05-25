import json

with open('D:/origin/MouseInc2.10.21/MouseInc/MouseInc.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

for item in data['Hotkeys']:
    if item.get('Keys') == 'Ctrl+Alt+O':
        item['Actions'] = [
            ['Snapshot', 'ToClipboard'],
            ['Internal', 'Delay', '300'],
            ['Execute', 'powershell -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "D:\\ClaudeCode\\scripts\\ocr-clipboard.ps1"', 'hide|wait'],
            ['Internal', 'Delay', '200'],
            ['SendKeys', 'Ctrl+V']
        ]
        print('Updated:', item['Name'])
        break

with open('D:/origin/MouseInc2.10.21/MouseInc/MouseInc.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent='\t')
print('Done')
