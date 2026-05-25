import json

with open('D:/origin/MouseInc2.10.21/MouseInc/MouseInc.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

for item in data['MatchGlobal']:
    if item.get('Sign') == 'SQUARE 2':
        item['Actions'] = [
            ['Screenshot', 'ToClipboard'],
            ['Internal', 'Delay', '300'],
            ['Execute', 'powershell -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "D:\\ClaudeCode\\scripts\\ocr-clipboard.ps1"', 'hide|wait'],
            ['Internal', 'ShowTips', 'OCR结果', '%clipboard%']
        ]
        print('Updated')
        break

with open('D:/origin/MouseInc2.10.21/MouseInc/MouseInc.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent='\t')
print('Done')
