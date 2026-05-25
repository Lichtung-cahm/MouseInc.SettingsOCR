import json

with open('D:/origin/MouseInc2.10.21/MouseInc/MouseInc.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

done_left = False
done_right = False
done_square2 = False
new_global = []

for item in data['MatchGlobal']:
    sign = item.get('Sign', '')

    if sign == 'LEFT':
        if not done_left:
            item['Actions'] = [['SendKeys', 'back']]
            item['Name'] = '后退'
            item['Valid'] = True
            new_global.append(item)
            done_left = True
            print('Fixed LEFT: 后退')
        else:
            print('Removed duplicate LEFT:', item.get('Name'))
        continue

    if sign == 'RIGHT':
        if not done_right:
            item['Actions'] = [
                ['Execute', 'powershell -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "D:\\ClaudeCode\\scripts\\save-clipboard.ps1"', 'hide|wait'],
                ['Internal', 'Delay', '200'],
                ['SendKeys', 'Ctrl+V']
            ]
            item['Name'] = '贴图到CC'
            item['Valid'] = True
            new_global.append(item)
            done_right = True
            print('Fixed RIGHT: 贴图到CC')
        else:
            print('Removed duplicate RIGHT:', item.get('Name'))
        continue

    if sign == 'SQUARE 2':
        if not done_square2:
            item['Actions'] = [
                ['Screenshot', 'ToClipboard'],
                ['Internal', 'Delay', '200'],
                ['Execute', 'powershell -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "D:\\ClaudeCode\\scripts\\save-clipboard.ps1"', 'hide|wait'],
                ['Internal', 'Delay', '200'],
                ['SendKeys', 'Ctrl+V']
            ]
            item['Name'] = '截图贴图'
            item['Valid'] = True
            new_global.append(item)
            done_square2 = True
            print('Fixed SQUARE 2: 截图贴图')
        else:
            print('Removed duplicate SQUARE 2:', item.get('Name'))
        continue

    new_global.append(item)

data['MatchGlobal'] = new_global

with open('D:/origin/MouseInc2.10.21/MouseInc/MouseInc.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent='\t')
print('Done')
