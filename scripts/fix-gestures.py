import json

with open('D:/origin/MouseInc2.10.21/MouseInc/MouseInc.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

new_global = []
left_done = False
right_done = False

for item in data['MatchGlobal']:
    sign = item.get('Sign', '')

    if sign == 'LEFT':
        if not left_done:
            item['Actions'] = [
                ['Execute', 'powershell -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "D:\\ClaudeCode\\scripts\\save-clipboard.ps1"', 'hide|wait'],
                ['Internal', 'Delay', '200'],
                ['SendKeys', 'Ctrl+V']
            ]
            item['Name'] = '贴图到CC'
            item['Valid'] = True
            new_global.append(item)
            left_done = True
            print('Fixed LEFT: 贴图到CC')
        else:
            print('Removed duplicate LEFT:', item.get('Name'))
        continue

    if sign == 'RIGHT':
        if not right_done:
            item['Actions'] = [
                ['Execute', 'powershell -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "D:\\ClaudeCode\\scripts\\ocr-clipboard.ps1"', 'hide|wait'],
                ['Internal', 'Delay', '500'],
                ['SendKeys', 'Ctrl+V']
            ]
            item['Name'] = 'OCR识别'
            item['Valid'] = True
            new_global.append(item)
            right_done = True
            print('Fixed RIGHT: OCR识别')
        else:
            print('Removed duplicate RIGHT:', item.get('Name'))
        continue

    new_global.append(item)

data['MatchGlobal'] = new_global

with open('D:/origin/MouseInc2.10.21/MouseInc/MouseInc.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent='\t')
print('Done')
