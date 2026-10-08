-- UI.lua


local api = WorldMarkerCyclerAPI
local targetApi = WorldMarkerCyclerTargetAPI
local mouseoverApi = WorldMarkerCyclerMouseoverAPI
local f -- forward declare frame

-- Locale table for UI strings
local L = setmetatable({}, { __index = function(t, k) return k end })
local locale = GetLocale()
if locale == "frFR" then
    L["World Marker Key Editor"] = "Editeur de raccourcis de marqueurs"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "TOUS LES RACCOURCIS PEUVENT ETRE DEFINIS ICI"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "Utilisez les champs ci-dessous pour definir les raccourcis pour les marqueurs mondiaux, de cible et de survol."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "Ordre de cycle des marqueurs (separe par des virgules):\nex. 1CARRE,2TRIANGLE,3DIAMANT,4CROIX,\n5ETOILE,6CERCLE,7LUNE,8CRANE"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "Remarque : Les raccourcis definis ici remplaceront ceux definis via les commandes ou autres interfaces."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "Tous les marqueurs et les numeros ci-dessus representent l'ordre qui sera utilise lorsque vous appuierez sur les raccourcis pour la premiere fois. Par exemple, si vous mettez 8, le marqueur crane sera toujours place en premier apres avoir tout efface. Cet ordre est desormais partage par les marqueurs au sol, de cible et de survol."
    L["World Cycle Key:"] = "Raccourci cycle mondial :"
    L["World Clear Key:"] = "Raccourci effacer mondial :"
    L["Target Cycle Key:"] = "Raccourci cycle cible :"
    L["Target Clear Key:"] = "Raccourci effacer cible :"
    L["Mouseover Cycle Key:"] = "Raccourci cycle survol :"
    L["Mouseover Clear Key:"] = "Raccourci effacer survol :"
    L["Raid Picker Open Key:"] = "Raccourci ouverture selecteur raid :"
elseif locale == "zhCN" then
    -- Simplified Chinese
    L["World Marker Key Editor"] = "世界标记按键编辑器"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "所有快捷键都可以在此页面设置"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "使用下面的输入框设置世界标记、目标标记和鼠标悬停标记的快捷键。"
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "标记循环顺序（用逗号分隔）：\n例如：1方块,2三角,3菱形,4十字,\n5星星,6圆形,7月亮,8骷髅"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "注意：这里设置的快捷键将覆盖通过命令或其他界面设置的快捷键。"
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "上方的所有标记及其数字表示第一次按下快捷键时的循环顺序。例如，如果你输入8，则骷髅标记会始终首先出现，并且在清除所有标记后也会再次优先放置。此顺序现在由地面、目标和鼠标悬停标记共用。"
    L["World Cycle Key:"] = "世界循环键："
    L["World Clear Key:"] = "清除世界标记键："
    L["Target Cycle Key:"] = "目标循环键："
    L["Target Clear Key:"] = "清除目标标记键："
    L["Mouseover Cycle Key:"] = "鼠标悬停循环键："
    L["Mouseover Clear Key:"] = "清除鼠标悬停标记键："
    L["Raid Picker Open Key:"] = "打开团队标记选择器键："

elseif locale == "zhTW" then
    -- Traditional Chinese
    L["World Marker Key Editor"] = "世界標記按鍵編輯器"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "所有快捷鍵都可以在此頁面設定"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "使用下面的輸入框設定世界標記、目標標記與滑鼠懸停標記的快捷鍵。"
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "標記循環順序（以逗號分隔）：\n例如：1方塊,2三角,3菱形,4十字,\n5星星,6圓形,7月亮,8骷髏"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "注意：此處設定的快捷鍵將覆蓋透過指令或其他介面設定的快捷鍵。"
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "上方的標記與數字表示第一次按下快捷鍵時的循環順序。例如輸入8，則骷髏標記會優先顯示，並在清除後再次優先放置。此順序現在由地面、目標和滑鼠懸停標記共用。"
    L["World Cycle Key:"] = "世界循環鍵："
    L["World Clear Key:"] = "清除世界標記鍵："
    L["Target Cycle Key:"] = "目標循環鍵："
    L["Target Clear Key:"] = "清除目標標記鍵："
    L["Mouseover Cycle Key:"] = "滑鼠懸停循環鍵："
    L["Mouseover Clear Key:"] = "清除滑鼠懸停標記鍵："
    L["Raid Picker Open Key:"] = "開啟團隊標記選擇器鍵："

elseif locale == "deDE" then
    -- German
    L["World Marker Key Editor"] = "Weltenmarkierungs-Tasteneditor"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "ALLE TASTENBELEGUNGEN KÖNNEN AUF DIESER SEITE FESTGELEGT WERDEN"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "Verwenden Sie die untenstehenden Eingabefelder, um Tastenbelegungen für Welt-, Ziel- und Mouseover-Markierungen festzulegen."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "Markierungsreihenfolge (durch Kommas getrennt):\nz. B. 1QUADRAT,2DREIECK,3RAUTE,4KREUZ,\n5STERN,6KREIS,7MOND,8SCHÄDEL"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "Hinweis: Hier gesetzte Tastenbelegungen überschreiben alle, die über Befehle oder andere Oberflächen gesetzt wurden."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "Alle Markierungen und Zahlen darüber stellen die Reihenfolge dar, die beim ersten Drücken der Taste verwendet wird. Wenn Sie z. B. 8 eingeben, wird der Schädel immer zuerst angezeigt und nach dem Löschen aller Markierungen erneut zuerst gesetzt. Diese Reihenfolge gilt jetzt für Boden-, Ziel- und Mouseover-Markierungen."
    L["World Cycle Key:"] = "Welt-Zyklus-Taste:"
    L["World Clear Key:"] = "Welt-Markierungen löschen:"
    L["Target Cycle Key:"] = "Ziel-Zyklus-Taste:"
    L["Target Clear Key:"] = "Ziel-Markierungen löschen:"
    L["Mouseover Cycle Key:"] = "Mouseover-Zyklus-Taste:"
    L["Mouseover Clear Key:"] = "Mouseover-Markierungen löschen:"
    L["Raid Picker Open Key:"] = "Raid-Markierungsmenü öffnen:"

elseif locale == "esES" or locale == "esMX" then
    -- Spanish (Spain + Latin America)
    L["World Marker Key Editor"] = "Editor de teclas de marcadores del mundo"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "TODAS LAS TECLAS SE PUEDEN CONFIGURAR EN ESTA PÁGINA"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "Usa los campos de abajo para configurar teclas para marcadores de mundo, objetivo y mouseover."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "Orden del ciclo de marcadores (separado por comas):\nej. 1CUADRADO,2TRIÁNGULO,3ROMBO,4CRUZ,\n5ESTRELLA,6CÍRCULO,7LUNA,8CALAVERA"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "Nota: Las teclas configuradas aquí sobrescribirán las establecidas mediante comandos u otras interfaces."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "Todos los marcadores y números representan el orden que se usará al presionar la tecla por primera vez. Por ejemplo, si pones 8, la calavera aparecerá primero y seguirá siendo la primera al limpiar todos los marcadores. Este orden ahora se comparte entre los marcadores de suelo, objetivo y mouseover."
    L["World Cycle Key:"] = "Tecla ciclo mundo:"
    L["World Clear Key:"] = "Tecla limpiar mundo:"
    L["Target Cycle Key:"] = "Tecla ciclo objetivo:"
    L["Target Clear Key:"] = "Tecla limpiar objetivo:"
    L["Mouseover Cycle Key:"] = "Tecla ciclo mouseover:"
    L["Mouseover Clear Key:"] = "Tecla limpiar mouseover:"
    L["Raid Picker Open Key:"] = "Tecla abrir selector de banda:"

elseif locale == "itIT" then
    -- Italian
    L["World Marker Key Editor"] = "Editor tasti marcatori del mondo"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "TUTTI I TASTI POSSONO ESSERE IMPOSTATI IN QUESTA PAGINA"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "Usa i campi qui sotto per impostare i tasti per marcatori del mondo, bersaglio e mouseover."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "Ordine ciclo marcatori (separato da virgole):\nes. 1QUADRATO,2TRIANGOLO,3ROMBO,4CROCE,\n5STELLA,6CERCHIO,7LUNA,8TESCHIO"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "Nota: I tasti impostati qui sovrascriveranno quelli impostati tramite comandi o altre interfacce."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "Tutti i marcatori e i numeri rappresentano l'ordine usato alla prima pressione. Se inserisci 8, il teschio sarà sempre il primo anche dopo aver pulito tutto. Questo ordine e ora condiviso da marcatori a terra, bersaglio e mouseover."
    L["World Cycle Key:"] = "Tasto ciclo mondo:"
    L["World Clear Key:"] = "Tasto pulizia mondo:"
    L["Target Cycle Key:"] = "Tasto ciclo bersaglio:"
    L["Target Clear Key:"] = "Tasto pulizia bersaglio:"
    L["Mouseover Cycle Key:"] = "Tasto ciclo mouseover:"
    L["Mouseover Clear Key:"] = "Tasto pulizia mouseover:"
    L["Raid Picker Open Key:"] = "Tasto apertura selettore raid:"

elseif locale == "ptBR" then
    -- Portuguese (Brazil)
    L["World Marker Key Editor"] = "Editor de teclas de marcadores do mundo"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "TODAS AS TECLAS PODEM SER CONFIGURADAS NESTA PÁGINA"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "Use os campos abaixo para configurar teclas para marcadores de mundo, alvo e mouseover."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "Ordem do ciclo de marcadores (separado por vírgulas):\nex. 1QUADRADO,2TRIÂNGULO,3LOSANGO,4CRUZ,\n5ESTRELA,6CÍRCULO,7LUA,8CAVEIRA"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "Nota: As teclas configuradas aqui substituirão quaisquer outras definidas por comandos ou outras interfaces."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "Todos os marcadores e números representam a ordem usada ao pressionar a tecla pela primeira vez. Se colocar 8, a caveira aparecerá primeiro e continuará sendo a primeira após limpar tudo. Esta ordem agora e compartilhada pelos marcadores no chão, de alvo e de mouseover."
    L["World Cycle Key:"] = "Tecla ciclo mundo:"
    L["World Clear Key:"] = "Tecla limpar mundo:"
    L["Target Cycle Key:"] = "Tecla ciclo alvo:"
    L["Target Clear Key:"] = "Tecla limpar alvo:"
    L["Mouseover Cycle Key:"] = "Tecla ciclo mouseover:"
    L["Mouseover Clear Key:"] = "Tecla limpar mouseover:"
    L["Raid Picker Open Key:"] = "Tecla abrir seletor de raide:"

elseif locale == "ruRU" then
    -- Russian
    L["World Marker Key Editor"] = "Редактор клавиш меток мира"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "ВСЕ КЛАВИШИ МОЖНО НАСТРОИТЬ НА ЭТОЙ СТРАНИЦЕ"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "Используйте поля ниже, чтобы назначить клавиши для мировых, целевых и mouseover-меток."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "Порядок цикла меток (через запятую):\nнапр. 1КВАДРАТ,2ТРЕУГОЛЬНИК,3РОМБ,4КРЕСТ,\n5ЗВЕЗДА,6КРУГ,7ЛУНА,8ЧЕРЕП"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "Примечание: назначенные здесь клавиши заменят те, что заданы через команды или другие интерфейсы."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "Все метки и числа обозначают порядок при первом нажатии. Если указать 8, череп всегда будет первым и после очистки снова станет первым. Этот порядок теперь общий для наземных меток, цели и наведения мыши."
    L["World Cycle Key:"] = "Клавиша цикла мира:"
    L["World Clear Key:"] = "Клавиша очистки мира:"
    L["Target Cycle Key:"] = "Клавиша цикла цели:"
    L["Target Clear Key:"] = "Клавиша очистки цели:"
    L["Mouseover Cycle Key:"] = "Клавиша цикла mouseover:"
    L["Mouseover Clear Key:"] = "Клавиша очистки mouseover:"
    L["Raid Picker Open Key:"] = "Клавиша открытия выбора рейда:"

elseif locale == "koKR" then
    -- Korean (draft - please have a native speaker review)
    L["World Marker Key Editor"] = "바닥 징표 단축키 편집기"
    L["ALL KEYBIND CAN BE SET IN THIS PAGE"] = "모든 단축키를 이 페이지에서 설정할 수 있습니다"
    L["Use the input boxes below to set keybindings for world, target, and mouseover markers."] = "아래 입력란에서 바닥 징표, 대상 징표, 마우스오버 징표의 단축키를 설정하세요."
    L["Marker Cycle Order (comma separated):\ne.g. 1SQUARE,2TRIANGLE,3DIAMOND,4CROSS,\n5STAR,6CIRCLE,7MOON,8SKULL"] = "징표 순환 순서 (쉼표로 구분):\n예) 1네모,2세모,3다이아몬드,4가위표,\n5별,6동그라미,7달,8해골"
    L["Note: Keybinds set here will override any keybinds set via slash commands or other UIs."] = "참고: 여기서 설정한 단축키는 명령어나 다른 UI에서 설정한 단축키보다 우선 적용됩니다."
    L["All Markers and Numbers above them represent the orderList that will be once you press the keybinds first time so when you clear all markers it will start from that first number you put into the input box for example if you put 8 it will mean skull marker will always show first and when you clear all markers skull will be placed first again this order is now shared by the ground, target and mouseover cyclers."] = "위의 징표와 숫자는 단축키를 처음 눌렀을 때 사용되는 순환 순서입니다. 예를 들어 8을 입력하면 해골 징표가 항상 먼저 표시되고, 모든 징표를 지운 뒤에도 해골이 다시 먼저 놓입니다. 이 순서는 이제 바닥, 대상, 마우스오버 징표가 함께 사용합니다."
    L["World Cycle Key:"] = "바닥 징표 순환 키:"
    L["World Clear Key:"] = "바닥 징표 지우기 키:"
    L["Target Cycle Key:"] = "대상 징표 순환 키:"
    L["Target Clear Key:"] = "대상 징표 지우기 키:"
    L["Mouseover Cycle Key:"] = "마우스오버 징표 순환 키:"
    L["Mouseover Clear Key:"] = "마우스오버 징표 지우기 키:"
    L["Raid Picker Open Key:"] = "공격대 징표 선택기 열기 키:"
    L["Marker bar: two rows"] = "징표 바: 두 줄"
    L["Splits the bar so the markers sit above the action buttons."] = "바를 둘로 나누어 징표가 행동 단축바 버튼 위에 오도록 합니다."
    L["Marker bar layout will change when you leave combat."] = "징표 바 배치는 전투가 끝나면 변경됩니다."
    -- Full menu (added for complete Korean UI)
    L["Overview"] = "개요"
    L["Ground Markers"] = "바닥 징표"
    L["Target"] = "대상"
    L["Mouseover"] = "마우스오버"
    L["Cycle Order"] = "순환 순서"
    L["Ground markers, target and mouseover each have their own cycle order. Pick which one to edit. After a clear, the cycle restarts at slot 1."] = "바닥 징표, 대상, 마우스오버는 각각 자신만의 순환 순서를 가집니다. 편집할 항목을 고르세요. 지운 뒤에는 1번 칸부터 다시 시작합니다."
    L["Editing:"] = "편집 중:"
    L["Ground markers"] = "바닥 징표"
    L["Raid Bar"] = "공격대 바"
    L["Help"] = "도움말"
    L["/wmc to open\nESC to close\n\nPreviews use your\nlive settings."] = "/wmc 로 열기\nESC 로 닫기\n\n미리보기는 현재\n설정을 사용합니다."
    L["Settings"] = "설정"
    L["Square"] = "네모"
    L["Triangle"] = "세모"
    L["Diamond"] = "다이아몬드"
    L["Cross"] = "가위표"
    L["Star"] = "별"
    L["Circle"] = "동그라미"
    L["Moon"] = "달"
    L["Skull"] = "해골"
    L["Defias Thug"] = "데피아즈단 폭력배"
    L["Kobold Geomancer"] = "코볼트 풍수사"
    L["Murloc Tidehunter"] = "멀록 파도사냥꾼"
    L["Press a key or mouse button"] = "키 또는 마우스 버튼을 누르세요"
    L["CTRL / ALT / SHIFT combos work.  ESC or left-click cancels."] = "CTRL / ALT / SHIFT 조합을 쓸 수 있습니다.  ESC 또는 왼쪽 클릭으로 취소합니다."
    L["Press a key for: %s"] = "키를 누르세요: %s"
    L["|cff777777Not bound|r"] = "|cff777777지정 안 됨|r"
    L["click to bind  ·  right-click to clear"] = "클릭하여 지정  ·  오른쪽 클릭하여 해제"
    L["|cffffd100Press a key...|r"] = "|cffffd100키를 누르세요...|r"
    L["LIVE PREVIEW"] = "실시간 미리보기"
    L["PAUSED"] = "일시정지"
    L["Live preview"] = "실시간 미리보기"
    L["Uses your current keys and marker order. Click to pause."] = "현재 단축키와 징표 순서를 사용합니다. 클릭하면 일시정지합니다."
    L["|cffffd100%s|r  places  %s %s  |cff888888(%s of %s)|r"] = "|cffffd100%s|r  키로  %s %s 배치  |cff888888(%s / %s)|r"
    L["Point at the ground and press your cycle key"] = "바닥을 가리키고 순환 키를 누르세요"
    L["|cffffd100%s|r  clears all  ·  next press starts at %s %s"] = "|cffffd100%s|r  모두 지우기  ·  다음에 누르면 %s %s 부터 시작"
    L["Target a mob  |cff888888(TAB or click)|r"] = "몹을 대상으로 지정하세요  |cff888888(TAB 또는 클릭)|r"
    L["|cffffd100%s|r  marks your target with  %s %s"] = "|cffffd100%s|r  키로 대상에  %s %s 징표 지정"
    L["|cffffd100%s|r  removes the mark from your target"] = "|cffffd100%s|r  키로 대상의 징표 제거"
    L["Hover + |cffffd100%s|r  marks the mob under your mouse  %s"] = "마우스를 올리고 |cffffd100%s|r  마우스 아래 몹에 징표 지정  %s"
    L["Nothing hovered? |cffffd100%s|r marks your |cffffd100target|r instead  %s"] = "마우스 아래에 몹이 없나요? |cffffd100%s|r 키는 대신 |cffffd100대상|r에 징표를 지정합니다  %s"
    L["Hover + |cffffd100%s|r  removes that mob's mark"] = "마우스를 올리고 |cffffd100%s|r  그 몹의 징표 제거"
    L["Click %s then click the ground to drop it"] = "%s 클릭 후 바닥을 클릭해 놓으세요"
    L["|cffff6666CLEAR|r removes every ground marker"] = "|cffff6666CLEAR|r 버튼은 모든 바닥 징표를 제거합니다"
    L["Ready check  ·  pull timer  ·  cancel timer"] = "전투 준비 확인  ·  풀 타이머  ·  타이머 취소"
    L["NEXT"] = "다음"
    L["After the last marker the cycle wraps back to slot |cffffd1001|r"] = "마지막 징표 다음에는 |cffffd1001|r번 칸으로 돌아갑니다"
    L["Each press of |cffffd100%s|r places the next marker in this order"] = "|cffffd100%s|r 를 누를 때마다 이 순서대로 다음 징표를 놓습니다"
    L["|cffffd100%s|r  resets the cycle  ·  next press is slot |cffffd1001|r again"] = "|cffffd100%s|r  순환 초기화  ·  다음에 누르면 다시 |cffffd1001|r번 칸"
    L["ON"] = "켬"
    L["OFF"] = "끔"
    L["Welcome to World Marker Cycler"] = "World Marker Cycler에 오신 것을 환영합니다"
    L["Place raid markers with a single key. Pick a section on the left - every page has a live preview of what it does."] = "키 하나로 공격대 징표를 놓으세요. 왼쪽에서 항목을 고르세요 - 모든 페이지에 기능을 보여주는 실시간 미리보기가 있습니다."
    L["Cycle: |cffffffff%s|r   Clear: |cffffffff%s|r"] = "순환: |cffffffff%s|r   지우기: |cffffffff%s|r"
    L["Target Markers"] = "대상 징표"
    L["Mouseover Markers"] = "마우스오버 징표"
    L["Raid Marker Bar"] = "공격대 징표 바"
    L["Open key: |cffffffff%s|r"] = "열기 키: |cffffffff%s|r"
    L["|cffffd100Tip:|r you must be group leader or assistant (or solo) for markers to appear. Blizzard allows about 3 marker actions per second."] = "|cffffd100팁:|r 징표를 놓으려면 파티장/공격대장 또는 부공격대장이어야 합니다 (혼자일 때도 가능). 블리자드는 초당 약 3회의 징표 동작만 허용합니다."
    L["Drops world markers on the ground at your mouse cursor. Each press places the next marker; the clear key removes them all."] = "마우스 커서 위치의 바닥에 징표를 놓습니다. 누를 때마다 다음 징표를 놓고, 지우기 키로 모두 제거합니다."
    L["Enable ground marker keybinds"] = "바닥 징표 단축키 사용"
    L["Click edge:"] = "클릭 시점:"
    L["Auto"] = "자동"
    L["Up"] = "뗄 때"
    L["Down"] = "누를 때"
    L["Auto detects keyboard vs mouse.  Up = keyboard keys.  Down = MMO mouse / extra mouse buttons."] = "자동 = 키보드와 마우스를 알아서 구분.  뗄 때 = 키보드 키.  누를 때 = MMO 마우스 / 추가 마우스 버튼."
    L["Puts a raid icon over your current target. Press again on a new target to give it the next icon in your order."] = "현재 대상 위에 공격대 징표를 붙입니다. 새 대상에서 다시 누르면 순서상 다음 징표를 붙입니다."
    L["Enable target marker keybinds"] = "대상 징표 단축키 사용"
    L["Marks the unit under your mouse (enemy or friendly) without changing target. With nothing hovered it marks your target instead."] = "대상을 바꾸지 않고 마우스 아래의 유닛(적 또는 아군)에게 징표를 붙입니다. 마우스 아래에 아무도 없으면 대신 현재 대상에 붙입니다."
    L["Enable mouseover marker keybinds"] = "마우스오버 징표 단축키 사용"
    L["The order markers are placed in. Shared by ground, target and mouseover cycling. After a clear, the cycle restarts at slot 1."] = "징표가 놓이는 순서입니다. 바닥, 대상, 마우스오버 순환이 함께 사용합니다. 지운 뒤에는 1번 칸부터 다시 시작합니다."
    L["Full order  |cff888888(click two slots to swap them)|r"] = "전체 순서  |cff888888(두 칸을 클릭하면 서로 바뀝니다)|r"
    L["Slot %s: %s"] = "%s번 칸: %s"
    L["Click, then click another slot to swap."] = "클릭한 뒤 다른 칸을 클릭하면 서로 바뀝니다."
    L["Or type it:"] = "또는 입력:"
    L["Reset default"] = "기본값으로"
    L["1 Square  2 Triangle  3 Diamond  4 Cross  5 Star  6 Circle  7 Moon  8 Skull"] = "1 네모  2 세모  3 다이아몬드  4 가위표  5 별  6 동그라미  7 달  8 해골"
    L["Custom Cycle Mode  |cff888888(only cycle a few markers)|r"] = "사용자 순환 모드  |cff888888(일부 징표만 순환)|r"
    L["Use a custom subset instead of the full order"] = "전체 순서 대신 고른 징표만 사용"
    L["|cffff4444World Marker Cycler: keep at least one marker in the custom cycle.|r"] = "|cffff4444World Marker Cycler: 사용자 순환에는 징표가 최소 하나 있어야 합니다.|r"
    L["Click to add / remove. New markers go to the end."] = "클릭하여 추가 / 제거. 새 징표는 맨 뒤에 들어갑니다."
    L["Order:"] = "순서:"
    L["|cff4de680Active:|r %s"] = "|cff4de680사용 중:|r %s"
    L["|cff888888Off - using the full 8-marker order|r"] = "|cff888888꺼짐 - 전체 8개 징표 순서 사용 중|r"
    L["A small bar with every ground marker, CLEAR, ready check and pull-timer buttons. Click a marker, then click the ground."] = "모든 바닥 징표, CLEAR, 전투 준비 확인, 풀 타이머 버튼이 있는 작은 바입니다. 징표를 클릭한 뒤 바닥을 클릭하세요."
    L["Enable the open-bar keybind"] = "바 열기 단축키 사용"
    L["Show / Hide bar"] = "바 표시 / 숨기기"
    L["Lock / Unlock"] = "잠금 / 잠금 해제"
    L["Bar is |cffffd100locked|r"] = "바가 |cffffd100잠겨|r 있습니다"
    L["Bar is |cff4de680unlocked|r - drag to move, right-click to lock"] = "바 |cff4de680잠금 해제됨|r - 드래그로 이동, 오른쪽 클릭으로 잠금"
    L["Help & Commands"] = "도움말 및 명령어"
    L["Slash commands, mouse button names and good-to-know limits."] = "슬래시 명령어, 마우스 버튼 이름, 알아두면 좋은 제한 사항."
    L["Slash commands"] = "슬래시 명령어"
    L["Open this window"] = "이 창 열기"
    L["Print your current keys and order"] = "현재 단축키와 순서를 채팅창에 출력"
    L["Clear all override keybinds and reset the cycle"] = "모든 단축키를 지우고 순환 초기화"
    L["Change the click edge for the cycle key"] = "순환 키의 클릭 시점 변경"
    L["Show / hide the raid marker bar"] = "공격대 징표 바 표시 / 숨기기"
    L["Lock or unlock the raid marker bar"] = "공격대 징표 바 잠금 / 잠금 해제"
    L["Toggle one or two rows on the bar"] = "바를 한 줄 / 두 줄로 전환"
    L["Set how many seconds the pull-timer button counts"] = "풀 타이머 버튼의 시간(초) 설정"
    L["Old key commands - the menu does this for you now"] = "예전 단축키 명령어 - 이제 메뉴에서 설정할 수 있습니다"
    L["Mouse button names"] = "마우스 버튼 이름"
    L["Wheel up"] = "휠 위로"
    L["Wheel down"] = "휠 아래로"
    L["Middle button"] = "가운데 버튼"
    L["Side button 4"] = "측면 버튼 4"
    L["Side button 5"] = "측면 버튼 5"
    L["Extra buttons"] = "추가 버튼"
    L["Combine with |cffffd100CTRL-|r, |cffffd100ALT-|r or |cffffd100SHIFT-|r, e.g. |cffffd100CTRL-MOUSEWHEELDOWN|r. The easiest way is just clicking a key box and pressing the combo."] = "|cffffd100CTRL-|r, |cffffd100ALT-|r 또는 |cffffd100SHIFT-|r 와 조합할 수 있습니다. 예: |cffffd100CTRL-MOUSEWHEELDOWN|r. 가장 쉬운 방법은 키 칸을 클릭하고 조합을 누르는 것입니다."
    L["|cffff6666Blizzard limit:|r about 3 world marker actions per second. Extra presses are ignored, so this addon throttles for you. Keybinds set here override bindings made with slash commands."] = "|cffff6666블리자드 제한:|r 바닥 징표 동작은 초당 약 3회입니다. 초과 입력은 무시되므로 이 애드온이 자동으로 속도를 조절합니다. 여기서 설정한 단축키는 슬래시 명령어로 만든 단축키보다 우선합니다."
    L["by CKRAIGFRIEND"] = "제작: CKRAIGFRIEND"
    L["one-key raid markers for ground, target and mouseover"] = "바닥, 대상, 마우스오버용 원키 공격대 징표"
    L["Open World Marker Cycler"] = "World Marker Cycler 열기"
    L["or type |cffffd100/wmc|r in chat"] = "또는 채팅창에 |cffffd100/wmc|r 입력"
    L["Quick toggles"] = "빠른 설정"
    L["Ground markers"] = "바닥 징표"
    L["Target markers"] = "대상 징표"
    L["Mouseover markers"] = "마우스오버 징표"
    L["Raid bar keybind"] = "공격대 바 단축키"
    L["Some features are enabled but don't have keybinds yet.\nOpen the settings to set them, or turn off what you don't use."] = "일부 기능이 켜져 있지만 아직 단축키가 없습니다.\n설정을 열어 지정하거나, 쓰지 않는 기능은 끄세요."
    L["Open settings"] = "설정 열기"
    L["Don't show again"] = "다시 보지 않기"
end

-- ==========================================================
-- WorldMarkerCycler - UI.lua (v2 menu)
--  * Styled popup window "WMC_ConfigFrame" with sidebar tabs
--  * Live animated previews built in Lua (no external media)
--  * Slim launcher page inside Blizzard's AddOns settings
-- Works on Retail and WoW Classic / Forever (modern engine).
-- Open with /wmc, /wmckey or /wmcconfig
-- ==========================================================

local api          = WorldMarkerCyclerAPI
local targetApi    = WorldMarkerCyclerTargetAPI
local mouseoverApi = WorldMarkerCyclerMouseoverAPI
local f -- Blizzard settings canvas (slim launcher)

-- ==========================================================
-- Data
-- ==========================================================
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
-- World marker index (/wm N) -> look
local WM = {
    [1] = { name = "Square",   icon = ICON .. "6", color = { 0.25, 0.55, 1.00 } },
    [2] = { name = "Triangle", icon = ICON .. "4", color = { 0.25, 0.90, 0.30 } },
    [3] = { name = "Diamond",  icon = ICON .. "3", color = { 0.80, 0.35, 1.00 } },
    [4] = { name = "Cross",    icon = ICON .. "7", color = { 1.00, 0.25, 0.20 } },
    [5] = { name = "Star",     icon = ICON .. "1", color = { 1.00, 0.90, 0.20 } },
    [6] = { name = "Circle",   icon = ICON .. "2", color = { 1.00, 0.55, 0.10 } },
    [7] = { name = "Moon",     icon = ICON .. "5", color = { 0.70, 0.80, 1.00 } },
    [8] = { name = "Skull",    icon = ICON .. "8", color = { 0.95, 0.95, 0.95 } },
}
local DEFAULT_ORDER = { 6, 4, 3, 7, 1, 2, 5, 8 }

-- Theme
local C = {
    bg      = { 0.055, 0.060, 0.075, 0.97 },
    side    = { 0.040, 0.045, 0.055, 1 },
    card    = { 0.085, 0.092, 0.110, 0.95 },
    border  = { 0.20, 0.22, 0.26, 1 },
    accent  = { 1.00, 0.78, 0.20 },
    text    = { 0.92, 0.92, 0.92 },
    dim     = { 0.58, 0.60, 0.65 },
    good    = { 0.30, 0.90, 0.45 },
    bad     = { 1.00, 0.35, 0.30 },
}

local FLAT     = "Interface\\Buttons\\WHITE8X8"
local CIRCLE   = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local SPARK    = "Interface\\Cooldown\\star4"
local BAR      = "Interface\\TargetingFrame\\UI-StatusBar"
local BACKDROP_TMPL = BackdropTemplateMixin and "BackdropTemplate" or nil

-- ==========================================================
-- Small helpers
-- ==========================================================
local function clamp(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end
local function lerp(a, b, t) return a + (b - a) * t end
local function easeOut(x) x = clamp(x); return 1 - (1 - x) ^ 3 end
local function easeInOut(x) x = clamp(x); if x < 0.5 then return 4 * x * x * x end return 1 - ((-2 * x + 2) ^ 3) / 2 end
local function backOut(x) x = clamp(x); local c1 = 1.70158; local c3 = c1 + 1; return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2 end
local function bounceOut(x)
    x = clamp(x)
    local n1, d1 = 7.5625, 2.75
    if x < 1 / d1 then return n1 * x * x
    elseif x < 2 / d1 then x = x - 1.5 / d1; return n1 * x * x + 0.75
    elseif x < 2.5 / d1 then x = x - 2.25 / d1; return n1 * x * x + 0.9375
    else x = x - 2.625 / d1; return n1 * x * x + 0.984375 end
end
-- 0..1..0 "blip" centred on c with half-width w
local function blip(t, c, w) return clamp(1 - math.abs((t - c) / w)) end

local function Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end
local function MarkerText(m) local d = WM[m] or WM[8]; return Hex(d.color) .. L[d.name] .. "|r" end
local function IconTag(m, size) return "|T" .. (WM[m] or WM[8]).icon .. ":" .. (size or 14) .. "|t" end

local function Skin(frame, bg, border, edge)
    if not frame.SetBackdrop then
        if BackdropTemplateMixin and Mixin then Mixin(frame, BackdropTemplateMixin) else return end
    end
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = edge or 1 })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    if border then frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1) end
end

local function SetGrad(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    tex:SetTexture(FLAT)
    if CreateColor and tex.SetGradient then
        local ok = pcall(tex.SetGradient, tex, orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
        if ok then return end
    end
    if tex.SetGradientAlpha then
        tex:SetGradientAlpha(orient, r1, g1, b1, a1, r2, g2, b2, a2)
    else
        tex:SetVertexColor(r2, g2, b2, a2)
    end
end

local function At(obj, parent, x, y)
    obj:ClearAllPoints()
    obj:SetPoint("CENTER", parent, "BOTTOMLEFT", x, y)
end

local function Text(parent, template, txt, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if txt then fs:SetText(type(txt) == "string" and L[txt] or txt) end
    if color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    fs:SetJustifyH("LEFT")
    return fs
end

-- ---------- saved-variable readers ----------
local function BindOf(sv, modKey, keyKey)
    if type(sv) ~= "table" then return "" end
    return (sv[modKey] or "") .. (sv[keyKey] or "")
end
local function WorldPlaceKey()  return BindOf(WMC_Saved, "placeModifier", "placeKey") end
local function WorldClearKey()  return BindOf(WMC_Saved, "clearModifier", "clearKey") end
local function TargetPlaceKey() return BindOf(WMC_TargetSaved, "placeModifier", "placeKey") end
local function TargetClearKey() return BindOf(WMC_TargetSaved, "clearModifier", "clearKey") end
local function MousePlaceKey()  return BindOf(WMC_MouseoverSaved, "placeModifier", "placeKey") end
local function MouseClearKey()  return BindOf(WMC_MouseoverSaved, "clearModifier", "clearKey") end
local function PickerKey()      return BindOf(WMC_RaidPickerSaved, "openModifier", "openKey") end
local function KeyOr(k, fallback) if k == "" then return fallback or "KEY" end return k end

-- Each cycler has its own cycle order: "world" (ground markers), "target",
-- "mouseover". OE.which = the one the Cycle Order page is editing.
local OE = { which = "world" }
local function OrderStore(which)
    which = which or OE.which
    if which == "target" then
        WMC_TargetSaved = WMC_TargetSaved or {}
        return WMC_TargetSaved, "cycleOrder"
    elseif which == "mouseover" then
        WMC_MouseoverSaved = WMC_MouseoverSaved or {}
        return WMC_MouseoverSaved, "cycleOrder"
    end
    WMC_Saved = WMC_Saved or {}
    return WMC_Saved, "orderList"
end
local function FullOrder(which)
    local s, k = OrderStore(which)
    local o = s[k]
    if type(o) == "table" and #o == 8 then return o end
    if (which or OE.which) ~= "world" then return FullOrder("world") end
    return DEFAULT_ORDER
end
local function CustomList(which)
    local s = OrderStore(which)
    local l = s.customCycleMarkers
    if type(l) == "table" and #l > 0 then return l end
    return { 8, 4, 3, 2 }
end
local function ActiveOrder(which)
    local s = OrderStore(which)
    if s.customCycleEnabled and type(s.customCycleMarkers) == "table" and #s.customCycleMarkers > 0 then
        return s.customCycleMarkers
    end
    return FullOrder(which)
end

local function FeatureOn(which)
    if which == "world"     then return not WMC_Saved or WMC_Saved.worldEnabled ~= false end
    if which == "target"    then return not WMC_TargetSaved or WMC_TargetSaved.enabled ~= false end
    if which == "mouseover" then return not WMC_MouseoverSaved or WMC_MouseoverSaved.enabled ~= false end
    if which == "raid"      then return not WMC_RaidPickerSaved or WMC_RaidPickerSaved.enabled ~= false end
    return false
end
local function SetFeature(which, val)
    if which == "world" then
        if api and api.SetWorldEnabled then api.SetWorldEnabled(val)
        else WMC_Saved = WMC_Saved or {}; WMC_Saved.worldEnabled = val end
    elseif which == "target" then
        local a = _G.WorldMarkerCyclerTargetAPI
        if a and a.SetEnabled then a.SetEnabled(val) else WMC_TargetSaved = WMC_TargetSaved or {}; WMC_TargetSaved.enabled = val end
    elseif which == "mouseover" then
        local a = _G.WorldMarkerCyclerMouseoverAPI
        if a and a.SetEnabled then a.SetEnabled(val) else WMC_MouseoverSaved = WMC_MouseoverSaved or {}; WMC_MouseoverSaved.enabled = val end
    elseif which == "raid" then
        local a = _G.WorldMarkerCyclerRaidPickerAPI
        if a and a.SetEnabled then a.SetEnabled(val) else WMC_RaidPickerSaved = WMC_RaidPickerSaved or {}; WMC_RaidPickerSaved.enabled = val end
    end
end

local function UpdateAllBindings()
    local list = { _G.WorldMarkerCyclerAPI, _G.WorldMarkerCyclerTargetAPI,
                   _G.WorldMarkerCyclerMouseoverAPI, _G.WorldMarkerCyclerRaidPickerAPI }
    for _, a in ipairs(list) do
        if a and a.UpdateBindings then pcall(a.UpdateBindings) end
    end
end

local function SyncOrders()
    local tApi = _G.WorldMarkerCyclerTargetAPI
    if tApi and tApi.SyncOrderFromWorld then tApi.SyncOrderFromWorld() end
    local mApi = _G.WorldMarkerCyclerMouseoverAPI
    if mApi and mApi.SyncOrderFromWorld then mApi.SyncOrderFromWorld() end
end

-- Every widget that shows saved state registers a refresher here
local refreshers = {}
local function RefreshAll()
    for _, fn in ipairs(refreshers) do pcall(fn) end
end

-- ==========================================================
-- Key Capture Overlay (IME-proof, press-to-bind)
-- ==========================================================
local keyCaptureFrame = CreateFrame("Button", "WMC_KeyCaptureOverlay", UIParent)
keyCaptureFrame:SetAllPoints(UIParent)
keyCaptureFrame:SetFrameStrata("FULLSCREEN_DIALOG")
keyCaptureFrame:EnableKeyboard(true)
keyCaptureFrame:EnableMouseWheel(true)
keyCaptureFrame:RegisterForClicks("AnyDown")
keyCaptureFrame:SetPropagateKeyboardInput(false)
keyCaptureFrame:Hide()

-- dim the screen + hint while capturing
do
    local dim = keyCaptureFrame:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.45)
    local hint = keyCaptureFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    hint:SetPoint("CENTER", 0, 120)
    hint:SetText(L["Press a key or mouse button"])
    local hint2 = keyCaptureFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint2:SetPoint("TOP", hint, "BOTTOM", 0, -8)
    hint2:SetText(L["CTRL / ALT / SHIFT combos work.  ESC or left-click cancels."])
    keyCaptureFrame.hint = hint
end

local function GetModifierString()
    local mod = ""
    if IsControlKeyDown() then mod = mod .. "CTRL-" end
    if IsAltKeyDown()     then mod = mod .. "ALT-" end
    if IsShiftKeyDown()   then mod = mod .. "SHIFT-" end
    return mod
end

local function FinishKeyCapture(mod, key)
    local handler = keyCaptureFrame._activeHandler
    keyCaptureFrame:Hide()
    if handler then handler(mod, key, mod .. key) end
    UpdateAllBindings()
    RefreshAll()
end

local function CancelKeyCapture()
    keyCaptureFrame:Hide()
    RefreshAll()
end

keyCaptureFrame:SetScript("OnKeyDown", function(_, key)
    if key == "ESCAPE" then CancelKeyCapture(); return end
    if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
    or key == "LALT" or key == "RALT" then return end
    FinishKeyCapture(GetModifierString(), key)
end)
keyCaptureFrame:SetScript("OnMouseWheel", function(_, delta)
    FinishKeyCapture(GetModifierString(), delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
end)
keyCaptureFrame:SetScript("OnClick", function(_, button)
    if button == "LeftButton" then CancelKeyCapture(); return end
    local map = { RightButton = "BUTTON2", MiddleButton = "BUTTON3", Button4 = "BUTTON4",
                  Button5 = "BUTTON5", Button6 = "BUTTON6", Button7 = "BUTTON7" }
    FinishKeyCapture(GetModifierString(), map[button] or button:upper())
end)
keyCaptureFrame:SetScript("OnHide", function() keyCaptureFrame._activeHandler = nil end)

local function StartKeyCapture(label, handler)
    keyCaptureFrame._activeHandler = handler
    keyCaptureFrame.hint:SetText(L["Press a key for: %s"]:format("|cffffd100" .. (label or "") .. "|r"))
    keyCaptureFrame:Show()
end

-- ==========================================================
-- Widgets
-- ==========================================================
local W = {}

function W.Card(parent, w, h, title)
    local c = CreateFrame("Frame", nil, parent, BACKDROP_TMPL)
    c:SetSize(w, h)
    Skin(c, C.card, C.border)
    if title then
        local t = Text(c, "GameFontNormal", title, C.accent)
        t:SetPoint("TOPLEFT", 12, -10)
        c.title = t
        local line = c:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.06)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", 10, -28)
        line:SetPoint("TOPRIGHT", -10, -28)
    end
    return c
end

-- Button in the flat style
function W.Button(parent, w, h, label, onClick, primary)
    local b = CreateFrame("Button", nil, parent, BACKDROP_TMPL)
    b:SetSize(w, h)
    local base = primary and { 0.55, 0.40, 0.05, 1 } or { 0.14, 0.15, 0.18, 1 }
    local edge = primary and { 1, 0.78, 0.2, 1 } or { 0.30, 0.32, 0.37, 1 }
    Skin(b, base, edge)
    b.text = b:CreateFontString(nil, "OVERLAY", primary and "GameFontNormal" or "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(L[label])
    b:SetScript("OnEnter", function(self) self:SetBackdropColor(base[1] + 0.08, base[2] + 0.08, base[3] + 0.08, 1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(base[1], base[2], base[3], 1) end)
    b:SetScript("OnMouseDown", function(self) self.text:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", 0, 0) end)
    if onClick then b:SetScript("OnClick", onClick) end
    function b:SetLabel(t) self.text:SetText(t) end
    return b
end

-- Modern on/off switch with a sliding knob
function W.Switch(parent, label, getter, setter, desc)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(300, desc and 36 or 22)

    local sw = CreateFrame("Button", nil, row, BACKDROP_TMPL)
    sw:SetSize(36, 18)
    sw:SetPoint("TOPLEFT", 0, -2)
    Skin(sw, { 0.2, 0.2, 0.22, 1 }, { 0.35, 0.36, 0.4, 1 })
    local knob = sw:CreateTexture(nil, "OVERLAY")
    knob:SetTexture(CIRCLE)
    knob:SetSize(14, 14)
    sw.knob = knob
    sw.pos = getter() and 1 or 0

    local lbl = Text(row, "GameFontHighlight", label)
    lbl:SetPoint("LEFT", sw, "RIGHT", 8, 0)
    if desc then
        local d = Text(row, "GameFontHighlightSmall", desc, C.dim)
        d:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -3)
        d:SetWidth(520)
    end

    local function Paint(p)
        knob:ClearAllPoints()
        knob:SetPoint("CENTER", sw, "LEFT", lerp(9, 27, p), 0)
        local on = { 0.20, 0.55, 0.28 }
        local off = { 0.20, 0.20, 0.22 }
        sw:SetBackdropColor(lerp(off[1], on[1], p), lerp(off[2], on[2], p), lerp(off[3], on[3], p), 1)
        knob:SetVertexColor(lerp(0.7, 1, p), lerp(0.7, 1, p), lerp(0.72, 1, p), 1)
    end
    Paint(sw.pos)

    sw:SetScript("OnUpdate", function(self, el)
        local want = getter() and 1 or 0
        if self.pos ~= want then
            local step = el * 7
            if self.pos < want then self.pos = math.min(want, self.pos + step)
            else self.pos = math.max(want, self.pos - step) end
            Paint(self.pos)
        end
    end)
    sw:SetScript("OnClick", function()
        setter(not getter())
        RefreshAll()
    end)
    row.switch = sw
    return row
end

local function PrettyKey(bind)
    if not bind or bind == "" then return L["|cff777777Not bound|r"] end
    return bind
end

-- Label + keycap. Left-click: capture. Right-click: unbind.
function W.KeyRow(parent, label, getBind, handler)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(560, 28)
    local lbl = Text(row, "GameFontHighlight", label)
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetWidth(200)

    local cap = CreateFrame("Button", nil, row, BACKDROP_TMPL)
    cap:SetSize(170, 24)
    cap:SetPoint("LEFT", 205, 0)
    Skin(cap, { 0.13, 0.14, 0.17, 1 }, { 0.40, 0.42, 0.47, 1 })
    -- bottom "key depth" line so it reads like a keyboard key
    local depth = cap:CreateTexture(nil, "ARTWORK")
    depth:SetColorTexture(0, 0, 0, 0.6)
    depth:SetHeight(3)
    depth:SetPoint("BOTTOMLEFT", 1, 1)
    depth:SetPoint("BOTTOMRIGHT", -1, 1)
    cap.text = cap:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cap.text:SetPoint("CENTER", 0, 1)
    cap:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hint = Text(row, "GameFontDisableSmall", "click to bind  ·  right-click to clear")
    hint:SetPoint("LEFT", cap, "RIGHT", 10, 0)

    cap:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
    cap:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.40, 0.42, 0.47, 1) end)
    cap:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if handler then handler("", "", "") end
            UpdateAllBindings()
            RefreshAll()
            return
        end
        self.text:SetText(L["|cffffd100Press a key...|r"])
        StartKeyCapture(label, handler)
    end)

    local function refresh() cap.text:SetText(PrettyKey(getBind())) end
    refresh()
    table.insert(refreshers, refresh)
    return row
end

-- Segmented control: options = { {label=, value=}, ... }
function W.Segmented(parent, options, getter, setter, segW)
    local holder = CreateFrame("Frame", nil, parent)
    segW = segW or 70
    holder:SetSize(segW * #options, 22)
    local btns = {}
    for i, opt in ipairs(options) do
        local b = CreateFrame("Button", nil, holder, BACKDROP_TMPL)
        b:SetSize(segW + (i > 1 and 1 or 0), 22)
        b:SetPoint("LEFT", (i - 1) * segW - (i > 1 and 1 or 0), 0)
        Skin(b, { 0.13, 0.14, 0.17, 1 }, { 0.32, 0.34, 0.39, 1 })
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(L[opt.label])
        b:SetScript("OnClick", function() setter(opt.value); RefreshAll() end)
        btns[i] = b
    end
    local function refresh()
        local cur = getter()
        for i, opt in ipairs(options) do
            local sel = (opt.value == cur)
            if sel then
                btns[i]:SetBackdropColor(0.45, 0.33, 0.05, 1)
                btns[i]:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
                btns[i]:SetFrameLevel(holder:GetFrameLevel() + 2)
            else
                btns[i]:SetBackdropColor(0.13, 0.14, 0.17, 1)
                btns[i]:SetBackdropBorderColor(0.32, 0.34, 0.39, 1)
                btns[i]:SetFrameLevel(holder:GetFrameLevel() + 1)
            end
        end
    end
    refresh()
    table.insert(refreshers, refresh)
    return holder
end

function W.EditBox(parent, w)
    local e = CreateFrame("EditBox", nil, parent, BACKDROP_TMPL)
    e:SetSize(w, 22)
    Skin(e, { 0.03, 0.035, 0.045, 1 }, { 0.32, 0.34, 0.39, 1 })
    e:SetFontObject("GameFontHighlight")
    e:SetTextInsets(6, 6, 0, 0)
    e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
    e:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(0.32, 0.34, 0.39, 1) end)
    return e
end

-- ==========================================================
-- Preview engine
-- A preview is a clipped frame with a scene that is re-drawn
-- every frame from a looping timeline (t in seconds).
-- Scenes read the live saved settings each loop, so changes
-- you make show up in the animation right away.
-- ==========================================================
local SCENES = {}

local function NewGroundMarker(p)
    local o = {}
    o.glow = p.layer:CreateTexture(nil, "ARTWORK", nil, 1)
    o.glow:SetTexture(CIRCLE); o.glow:SetBlendMode("ADD")
    o.core = p.layer:CreateTexture(nil, "ARTWORK", nil, 2)
    o.core:SetTexture(CIRCLE); o.core:SetBlendMode("ADD")
    o.spark = p.layer:CreateTexture(nil, "ARTWORK", nil, 3)
    o.spark:SetTexture(SPARK); o.spark:SetBlendMode("ADD")
    o.icon = p.layer:CreateTexture(nil, "OVERLAY")
    o.icon:SetSize(24, 24)
    return o
end

-- u = pop progress (0 hidden .. 1 done), fade = alpha multiplier
local function DrawGroundMarker(o, p, m, x, y, u, fade, t)
    if u <= 0 or fade <= 0 then
        o.glow:Hide(); o.core:Hide(); o.spark:Hide(); o.icon:Hide()
        return
    end
    local c = (WM[m] or WM[8]).color
    local s = backOut(u)
    local a = clamp(u * 3) * fade
    o.glow:Show(); o.core:Show(); o.icon:Show()
    o.glow:SetSize(86 * s, 30 * s); At(o.glow, p.layer, x, y)
    o.glow:SetVertexColor(c[1], c[2], c[3], 0.40 * a)
    o.core:SetSize(46 * s, 15 * s); At(o.core, p.layer, x, y)
    o.core:SetVertexColor(c[1], c[2], c[3], 0.85 * a)
    local drop = lerp(62, 18, bounceOut(clamp(u * 1.2)))
    local bob = (u >= 1) and math.sin(t * 2.6 + x * 0.05) * 2 or 0
    o.icon:SetTexture((WM[m] or WM[8]).icon)
    o.icon:SetAlpha(a)
    At(o.icon, p.layer, x, y + drop + bob)
    if u < 1 then
        o.spark:Show()
        local su = easeOut(u)
        o.spark:SetSize(lerp(12, 96, su), lerp(12, 96, su) * 0.6)
        At(o.spark, p.layer, x, y)
        o.spark:SetVertexColor(c[1], c[2], c[3], (1 - u) * fade)
    else
        o.spark:Hide()
    end
end

local PORTRAITS = {
    "Interface\\Icons\\Spell_Shadow_RaiseDead",
    "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
}

local function NewPlate(p, name, hp, portrait)
    local pl = CreateFrame("Frame", nil, p.layer)
    pl:SetSize(110, 70)

    -- shadow + portrait "unit"
    local sh = pl:CreateTexture(nil, "BACKGROUND")
    sh:SetTexture(CIRCLE); sh:SetVertexColor(0, 0, 0, 0.6)
    sh:SetSize(60, 16); sh:SetPoint("BOTTOM", 0, -4)
    local por = pl:CreateTexture(nil, "ARTWORK")
    por:SetTexture(portrait)
    por:SetSize(34, 34); por:SetPoint("BOTTOM", 0, 2)
    if por.SetMask then pcall(por.SetMask, por, CIRCLE) end
    local ring = pl:CreateTexture(nil, "BORDER")
    ring:SetTexture(CIRCLE); ring:SetVertexColor(0.5, 0.1, 0.1, 1)
    ring:SetSize(38, 38); ring:SetPoint("CENTER", por, "CENTER")
    pl.ring = ring

    -- nameplate
    local plate = CreateFrame("Frame", nil, pl, BACKDROP_TMPL)
    plate:SetSize(100, 9)
    plate:SetPoint("BOTTOM", por, "TOP", 0, 6)
    Skin(plate, { 0, 0, 0, 0.85 }, { 0, 0, 0, 1 })
    local bar = plate:CreateTexture(nil, "ARTWORK")
    bar:SetTexture(BAR); bar:SetVertexColor(0.85, 0.12, 0.10)
    bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("BOTTOMLEFT", 1, 1)
    bar:SetWidth(98 * hp)
    local nm = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nm:SetPoint("BOTTOM", plate, "TOP", 0, 2)
    nm:SetText(L[name])

    -- target selection (gold frame) + mouseover glow
    local sel = CreateFrame("Frame", nil, plate, BACKDROP_TMPL)
    sel:SetPoint("TOPLEFT", -3, 3); sel:SetPoint("BOTTOMRIGHT", 3, -3)
    Skin(sel, { 0, 0, 0, 0 }, { 1, 0.82, 0.1, 1 }, 2)
    sel:SetAlpha(0)
    local hov = plate:CreateTexture(nil, "OVERLAY")
    hov:SetTexture(FLAT); hov:SetBlendMode("ADD"); hov:SetAllPoints()
    hov:SetVertexColor(1, 1, 1, 0)

    local mark = pl:CreateTexture(nil, "OVERLAY")
    mark:SetSize(22, 22)
    mark:SetPoint("BOTTOM", nm, "TOP", 0, 2)
    mark:Hide()
    local spark = pl:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(SPARK); spark:SetBlendMode("ADD")
    spark:SetPoint("CENTER", mark, "CENTER")
    spark:Hide()

    pl.sel, pl.hov, pl.mark, pl.spark = sel, hov, mark, spark
    return pl
end

-- selA: target frame alpha, hovA: mouseover glow, m: marker or nil, u: pop, fade
local function DrawPlate(pl, selA, hovA, m, u, fade)
    pl.sel:SetAlpha(selA)
    pl.hov:SetVertexColor(1, 1, 1, 0.35 * hovA)
    pl.ring:SetVertexColor(lerp(0.5, 1, selA), lerp(0.1, 0.8, selA), 0.1, 1)
    if not m or u <= 0 or fade <= 0 then pl.mark:Hide(); pl.spark:Hide(); return end
    local s = backOut(u)
    pl.mark:Show()
    pl.mark:SetTexture((WM[m] or WM[8]).icon)
    pl.mark:SetSize(22 * s, 22 * s)
    pl.mark:SetAlpha(clamp(u * 3) * fade)
    if u < 1 then
        pl.spark:Show()
        pl.spark:SetSize(lerp(10, 70, easeOut(u)), lerp(10, 70, easeOut(u)))
        local c = (WM[m] or WM[8]).color
        pl.spark:SetVertexColor(c[1], c[2], c[3], 1 - u)
    else
        pl.spark:Hide()
    end
end

local function DrawKey(p, text, press)
    local kc = p.keycap
    if not text then kc:Hide(); return end
    kc:Show()
    kc.text:SetText(text)
    kc:SetWidth(math.max(54, kc.text:GetStringWidth() + 22))
    kc:ClearAllPoints()
    kc:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -10, 10 - 3 * press)
    kc:SetBackdropColor(lerp(0.16, 0.55, press), lerp(0.17, 0.42, press), lerp(0.20, 0.08, press), 1)
    kc:SetBackdropBorderColor(lerp(0.45, 1, press), lerp(0.47, 0.82, press), lerp(0.52, 0.2, press), 1)
    kc.depth:SetAlpha(1 - press)
end

local function DrawCursor(p, x, y, kind, alpha)
    local cur = p.cursor
    if not x then cur:Hide(); p.reticle:Hide(); return end
    cur:Show()
    cur:SetAlpha(alpha or 1)
    cur:SetTexture(kind == "attack" and "Interface\\Cursor\\Attack" or "Interface\\Cursor\\Point")
    cur:ClearAllPoints()
    cur:SetPoint("TOPLEFT", p.layer, "BOTTOMLEFT", x, y)
    if kind == "reticle" then
        p.reticle:Show()
        At(p.reticle, p.layer, x, y)
    else
        p.reticle:Hide()
    end
end

local function CreatePreview(parent, w, h, sceneKey)
    local p = CreateFrame("Frame", nil, parent, BACKDROP_TMPL)
    p:SetSize(w, h)
    Skin(p, { 0.02, 0.025, 0.035, 1 }, C.border)
    if p.SetClipsChildren then p:SetClipsChildren(true) end

    local g = p:CreateTexture(nil, "BACKGROUND", nil, 1)
    g:SetPoint("TOPLEFT", 1, -1); g:SetPoint("BOTTOMRIGHT", -1, 1)
    SetGrad(g, "VERTICAL", 0.07, 0.085, 0.06, 1, 0.025, 0.03, 0.045, 1)

    p.layer = CreateFrame("Frame", nil, p)
    p.layer:SetAllPoints()
    p.top = CreateFrame("Frame", nil, p)
    p.top:SetAllPoints()
    p.top:SetFrameLevel(p.layer:GetFrameLevel() + 20)

    -- "LIVE PREVIEW" chip
    local chip = CreateFrame("Frame", nil, p.top, BACKDROP_TMPL)
    chip:SetSize(96, 16)
    chip:SetPoint("TOPLEFT", 8, -8)
    Skin(chip, { 0, 0, 0, 0.55 }, { 1, 1, 1, 0.08 })
    local dot = chip:CreateTexture(nil, "OVERLAY")
    dot:SetTexture(CIRCLE); dot:SetSize(7, 7); dot:SetPoint("LEFT", 6, 0)
    local ct = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ct:SetPoint("LEFT", dot, "RIGHT", 5, 0)
    ct:SetText(L["LIVE PREVIEW"])
    p.dot, p.chipText = dot, ct

    p.caption = Text(p.top, "GameFontHighlight", "")
    p.caption:SetPoint("BOTTOMLEFT", 12, 12)
    p.caption:SetPoint("RIGHT", p, "RIGHT", -120, 0)

    local kc = CreateFrame("Frame", nil, p.top, BACKDROP_TMPL)
    kc:SetSize(60, 24)
    Skin(kc, { 0.16, 0.17, 0.2, 1 }, { 0.45, 0.47, 0.52, 1 })
    kc.text = kc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kc.text:SetPoint("CENTER", 0, 1)
    kc.depth = kc:CreateTexture(nil, "ARTWORK")
    kc.depth:SetColorTexture(0, 0, 0, 0.7); kc.depth:SetHeight(3)
    kc.depth:SetPoint("BOTTOMLEFT", 1, 1); kc.depth:SetPoint("BOTTOMRIGHT", -1, 1)
    kc:Hide()
    p.keycap = kc

    p.reticle = p.top:CreateTexture(nil, "ARTWORK")
    p.reticle:SetTexture(CIRCLE); p.reticle:SetBlendMode("ADD")
    p.reticle:SetSize(46, 18); p.reticle:SetVertexColor(0.3, 1, 0.4, 0.55)
    p.reticle:Hide()
    p.cursor = p.top:CreateTexture(nil, "OVERLAY")
    p.cursor:SetSize(26, 26)
    p.cursor:Hide()

    p.scene = SCENES[sceneKey]
    p.scene.build(p)
    p.t, p.dur = 0, nil

    p:SetScript("OnUpdate", function(self, el)
        -- pulsing "live" dot
        local pulse = 0.55 + 0.45 * math.sin(GetTime() * 4)
        if self.paused then
            self.dot:SetVertexColor(1, 0.8, 0.2, 1)
            return
        end
        self.dot:SetVertexColor(1, 0.25, 0.2, pulse)
        self.t = self.t + math.min(el, 0.1)
        if not self.dur or self.t > self.dur then
            self.t = 0
            self.W, self.H = self:GetWidth(), self:GetHeight()
            self.scene.refresh(self)
        end
        self.scene.update(self, self.t)
    end)
    p:SetScript("OnShow", function(self) self.dur = nil end)
    p:EnableMouse(true)
    p:SetScript("OnMouseUp", function(self)
        self.paused = not self.paused
        self.chipText:SetText(self.paused and L["PAUSED"] or L["LIVE PREVIEW"])
    end)
    p:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:AddLine(L["Live preview"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Uses your current keys and marker order. Click to pause."], 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return p
end

-- ---------- Scene: ground (world) markers ----------
SCENES.world = {
    build = function(p)
        -- perspective floor lines
        p.lines = {}
        for i = 1, 5 do
            local ln = p.layer:CreateTexture(nil, "BACKGROUND", nil, 2)
            ln:SetColorTexture(1, 1, 1, 0.025 + i * 0.008)
            ln:SetHeight(1)
            p.lines[i] = ln
        end
        p.markers = {}
        for i = 1, 5 do p.markers[i] = NewGroundMarker(p) end
    end,
    refresh = function(p)
        local Wd, H = p.W, p.H
        for i, ln in ipairs(p.lines) do
            ln:ClearAllPoints()
            local y = H * (0.12 + (i - 1) ^ 1.35 * 0.075)
            ln:SetPoint("LEFT", p.layer, "BOTTOMLEFT", 0, y)
            ln:SetPoint("RIGHT", p.layer, "BOTTOMRIGHT", 0, y)
        end
        local order = ActiveOrder("world")
        p.order = order
        p.n = math.min(#order, 5)
        p.spots = {
            { Wd * 0.18, H * 0.34 }, { Wd * 0.38, H * 0.22 }, { Wd * 0.58, H * 0.36 },
            { Wd * 0.78, H * 0.24 }, { Wd * 0.47, H * 0.50 },
        }
        p.pk = KeyOr(WorldPlaceKey(), "B")
        p.ck = KeyOr(WorldClearKey(), "CTRL-B")
        p.t0, p.step = 0.5, 1.25
        p.tc = p.t0 + p.n * p.step + 0.5
        p.dur = p.tc + 1.6
    end,
    update = function(p, t)
        local n, t0, step, tc = p.n, p.t0, p.step, p.tc
        -- cursor path
        local start = { p.W * 0.08, p.H * 0.62 }
        local cx, cy = start[1], start[2]
        local cur = 0
        for k = 1, n do
            local st = t0 + (k - 1) * step
            if t >= st then
                cur = k
                local from = (k == 1) and start or p.spots[k - 1]
                local u = easeInOut((t - st) / 0.55)
                cx = lerp(from[1], p.spots[k][1], u)
                cy = lerp(from[2], p.spots[k][2], u)
            end
        end
        DrawCursor(p, cx, cy, "point")

        -- markers
        for k = 1, 5 do
            local o = p.markers[k]
            if k <= n then
                local a = t0 + (k - 1) * step + 0.65
                local u = clamp((t - a) / 0.45)
                local fade = 1 - clamp((t - tc - 0.1) / 0.45)
                DrawGroundMarker(o, p, p.order[k], p.spots[k][1], p.spots[k][2], (t >= a) and math.max(u, 0.001) or 0, fade, t)
            else
                DrawGroundMarker(o, p, 8, 0, 0, 0, 0, t)
            end
        end

        -- keycap + caption
        if t < tc - 0.2 then
            local press = 0
            for k = 1, n do press = math.max(press, blip(t, t0 + (k - 1) * step + 0.65, 0.12)) end
            DrawKey(p, p.pk, press)
            if cur >= 1 then
                local m = p.order[cur]
                p.caption:SetText(L["|cffffd100%s|r  places  %s %s  |cff888888(%s of %s)|r"]:format(p.pk, IconTag(m), MarkerText(m), tostring(cur), tostring(#p.order)))
            else
                p.caption:SetText(L["Point at the ground and press your cycle key"])
            end
        else
            DrawKey(p, p.ck, blip(t, tc, 0.14))
            p.caption:SetText(L["|cffffd100%s|r  clears all  ·  next press starts at %s %s"]:format(p.ck, IconTag(p.order[1]), MarkerText(p.order[1])))
        end
    end,
}

-- ---------- helpers shared by target / mouseover ----------
local MOBS = { { "Defias Thug", 0.92 }, { "Kobold Geomancer", 0.64 }, { "Murloc Tidehunter", 0.8 } }
local function BuildPlates(p)
    p.plates = {}
    for i = 1, 3 do p.plates[i] = NewPlate(p, MOBS[i][1], MOBS[i][2], PORTRAITS[i]) end
end
local function PlacePlates(p)
    local xs = { 0.2, 0.5, 0.8 }
    local ys = { 0.40, 0.50, 0.40 }
    p.px, p.py = {}, {}
    for i = 1, 3 do
        p.px[i], p.py[i] = p.W * xs[i], p.H * ys[i]
        At(p.plates[i], p.layer, p.px[i], p.py[i])
    end
end

-- ---------- Scene: target markers ----------
SCENES.target = {
    build = BuildPlates,
    refresh = function(p)
        PlacePlates(p)
        p.order = ActiveOrder("target")
        p.pk = KeyOr(TargetPlaceKey(), "KEY")
        p.ck = KeyOr(TargetClearKey(), "KEY")
        p.t0, p.step = 0.4, 1.6
        p.tc = p.t0 + 3 * p.step + 0.3
        p.dur = p.tc + 1.8
    end,
    update = function(p, t)
        local t0, step, tc = p.t0, p.step, p.tc
        local cur = 0
        for k = 1, 3 do if t >= t0 + (k - 1) * step then cur = k end end
        DrawCursor(p, nil)
        for i = 1, 3 do
            local st = t0 + (i - 1) * step
            local selA = 0
            if cur == i then selA = clamp((t - st) / 0.2) end
            local a = st + 0.8
            local u = (t >= a) and math.max(0.001, clamp((t - a) / 0.4)) or 0
            local fade = 1
            if i == 3 then fade = 1 - clamp((t - tc - 0.05) / 0.35) end
            fade = math.min(fade, 1 - clamp((t - (p.dur - 0.5)) / 0.4))
            DrawPlate(p.plates[i], selA, 0, p.order[i], u, fade)
        end
        -- keys: TAB to target, then cycle key
        if t < tc - 0.2 then
            local k = math.max(cur, 1)
            local st = t0 + (k - 1) * step
            if t < st + 0.45 then
                DrawKey(p, "TAB", blip(t, st + 0.05, 0.1))
                p.caption:SetText(L["Target a mob  |cff888888(TAB or click)|r"])
            else
                DrawKey(p, p.pk, blip(t, st + 0.8, 0.12))
                local m = p.order[k]
                p.caption:SetText(L["|cffffd100%s|r  marks your target with  %s %s"]:format(p.pk, IconTag(m), MarkerText(m)))
            end
        else
            DrawKey(p, p.ck, blip(t, tc, 0.14))
            p.caption:SetText(L["|cffffd100%s|r  removes the mark from your target"]:format(p.ck))
        end
    end,
}

-- ---------- Scene: mouseover markers ----------
SCENES.mouseover = {
    build = BuildPlates,
    refresh = function(p)
        PlacePlates(p)
        p.order = ActiveOrder("mouseover")
        p.pk = KeyOr(MousePlaceKey(), "KEY")
        p.ck = KeyOr(MouseClearKey(), "KEY")
        -- stops: hover plate 1, hover plate 3, empty ground (falls back to target = plate 2)
        p.stops = {
            { p.px[1] + 10, p.py[1] + 6, 1 },
            { p.px[3] + 10, p.py[3] + 6, 3 },
            { p.W * 0.5 + 6, p.H * 0.88, 0 },
        }
        p.t0, p.step = 0.5, 1.5
        p.tc = p.t0 + 3 * p.step + 0.9
        p.dur = p.tc + 1.6
    end,
    update = function(p, t)
        local t0, step, tc = p.t0, p.step, p.tc
        local start = { p.W * 0.5, p.H * 0.1 }
        local cx, cy, hover, cur = start[1], start[2], 0, 0
        for k = 1, 3 do
            local st = t0 + (k - 1) * step
            if t >= st then
                cur = k
                local from = (k == 1) and start or p.stops[k - 1]
                local u = easeInOut((t - st) / 0.5)
                cx, cy = lerp(from[1], p.stops[k][1], u), lerp(from[2], p.stops[k][2], u)
                hover = (u >= 0.95) and p.stops[k][3] or 0
            end
        end
        -- final: move back over plate 1 and clear it
        if t >= tc - 0.6 then
            local u = easeInOut((t - (tc - 0.6)) / 0.45)
            cx, cy = lerp(p.stops[3][1], p.stops[1][1], u), lerp(p.stops[3][2], p.stops[1][2], u)
            hover = (u >= 0.95) and 1 or 0
        end
        DrawCursor(p, cx, cy, hover > 0 and "attack" or "point")

        -- which plate gets which marker: stop1 -> plate1, stop2 -> plate3, stop3 -> plate2 (your target)
        local owner = { [1] = 1, [3] = 2, [2] = 3 }
        for i = 1, 3 do
            local k = owner[i]
            local a = t0 + (k - 1) * step + 0.7
            local u = (t >= a) and math.max(0.001, clamp((t - a) / 0.4)) or 0
            local fade = 1
            if i == 1 then fade = 1 - clamp((t - tc - 0.05) / 0.35) end
            fade = math.min(fade, 1 - clamp((t - (p.dur - 0.5)) / 0.4))
            DrawPlate(p.plates[i], (i == 2) and 1 or 0, (hover == i) and 1 or 0, p.order[k], u, fade)
        end

        if t < tc - 0.6 then
            local k = math.max(cur, 1)
            DrawKey(p, p.pk, blip(t, t0 + (k - 1) * step + 0.7, 0.12))
            local m = p.order[k]
            if k < 3 then
                p.caption:SetText(L["Hover + |cffffd100%s|r  marks the mob under your mouse  %s"]:format(p.pk, IconTag(m)))
            else
                p.caption:SetText(L["Nothing hovered? |cffffd100%s|r marks your |cffffd100target|r instead  %s"]:format(p.pk, IconTag(m)))
            end
        else
            DrawKey(p, p.ck, blip(t, tc, 0.14))
            p.caption:SetText(L["Hover + |cffffd100%s|r  removes that mob's mark"]:format(p.ck))
        end
    end,
}

-- ---------- Scene: raid marker bar ----------
SCENES.raidbar = {
    build = function(p)
        p.bar = CreateFrame("Frame", nil, p.layer, BACKDROP_TMPL)
        Skin(p.bar, { 0, 0, 0, 0.75 }, { 0.6, 0.6, 0.65, 0.8 })
        p.btns = {}
        for i = 1, 8 do
            local b = p.bar:CreateTexture(nil, "ARTWORK")
            b:SetTexture(WM[i].icon)
            b:SetSize(20, 20)
            p.btns[i] = b
        end
        p.clear = CreateFrame("Frame", nil, p.bar, BACKDROP_TMPL)
        Skin(p.clear, { 0.25, 0.06, 0.06, 1 }, { 0.5, 0.15, 0.15, 1 })
        p.clear:SetSize(38, 18)
        local ct = p.clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ct:SetPoint("CENTER"); ct:SetText("CLEAR")
        p.extras = {}
        local ex = { "Interface\\RaidFrame\\ReadyCheck-Ready", "Interface\\Icons\\INV_Misc_PocketWatch_01", "Interface\\RaidFrame\\ReadyCheck-NotReady" }
        for i = 1, 3 do
            local e = p.bar:CreateTexture(nil, "ARTWORK")
            e:SetTexture(ex[i]); e:SetSize(16, 16)
            p.extras[i] = e
        end
        p.press = p.bar:CreateTexture(nil, "OVERLAY")
        p.press:SetTexture(FLAT); p.press:SetBlendMode("ADD")
        p.markers = {}
        for i = 1, 3 do p.markers[i] = NewGroundMarker(p) end
        p.count = CreateFrame("Frame", nil, p.layer)
        p.count:SetSize(80, 60)
        p.count.text = p.count:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        p.count.text:SetPoint("CENTER")
    end,
    refresh = function(p)
        local rows = (WMC_RaidPickerSaved and WMC_RaidPickerSaved.rows) or 1
        local api2 = _G.WorldMarkerCyclerRaidPickerAPI
        if api2 and api2.GetRows then rows = api2.GetRows() or rows end
        p.rows = rows
        local bw, bh
        if rows == 2 then bw, bh = 8 * 24 + 12, 54 else bw, bh = 8 * 24 + 44 + 3 * 20 + 20, 30 end
        p.bar:SetSize(bw, bh)
        p.bar:ClearAllPoints()
        p.bar:SetPoint("TOP", p.layer, "TOP", 0, -30)
        p.bx, p.by = {}, {}
        local topY = (rows == 2) and -4 or -5
        for i = 1, 8 do
            local b = p.btns[i]
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", p.bar, "TOPLEFT", 6 + (i - 1) * 24, topY)
        end
        p.clear:ClearAllPoints()
        if rows == 2 then
            p.clear:SetPoint("TOPLEFT", p.bar, "TOPLEFT", 6, -30)
            for i = 1, 3 do
                p.extras[i]:ClearAllPoints()
                p.extras[i]:SetPoint("LEFT", p.clear, "RIGHT", 6 + (i - 1) * 20, 0)
            end
        else
            p.clear:SetPoint("LEFT", p.btns[8], "RIGHT", 6, 0)
            for i = 1, 3 do
                p.extras[i]:ClearAllPoints()
                p.extras[i]:SetPoint("LEFT", p.clear, "RIGHT", 4 + (i - 1) * 20, 0)
            end
        end
        -- screen-space targets (bar is centred at top)
        local left = p.W / 2 - bw / 2
        local top = p.H - 30
        for i = 1, 8 do
            p.bx[i] = left + 6 + (i - 1) * 24 + 10
            p.by[i] = top + topY - 10
        end
        if rows == 2 then p.clx, p.cly = left + 6 + 19, top - 39
        else p.clx, p.cly = left + 6 + 8 * 24 + 19, top - 15 end
        p.cdx, p.cdy = p.clx + 19 + 4 + 20 + 8, p.cly

        local o = ActiveOrder("world")
        p.pick = { o[1], o[2] or o[1], o[3] or o[1] }
        p.spots = { { p.W * 0.25, p.H * 0.22 }, { p.W * 0.5, p.H * 0.30 }, { p.W * 0.75, p.H * 0.20 } }
        p.step = 1.8
        p.tclear = 0.4 + 3 * p.step
        p.tcount = p.tclear + 1.2
        p.dur = p.tcount + 2.6
    end,
    update = function(p, t)
        local step = p.step
        local cx, cy, kind = p.W * 0.5, p.H * 0.1, "point"
        local pressX, pressA = 0, 0
        local prev = { cx, cy }
        for k = 1, 3 do
            local st = 0.4 + (k - 1) * step
            if t >= st then
                local m = p.pick[k]
                local bx, by = p.bx[m], p.by[m]
                local u1 = easeInOut((t - st) / 0.5)
                local u2 = easeInOut((t - st - 0.75) / 0.55)
                if t < st + 0.75 then
                    cx, cy = lerp(prev[1], bx, u1), lerp(prev[2], by, u1)
                    kind = "point"
                else
                    cx, cy = lerp(bx, p.spots[k][1], u2), lerp(by, p.spots[k][2], u2)
                    kind = (t < st + 1.45) and "reticle" or "point"
                end
                local pa = blip(t, st + 0.6, 0.1)
                if pa > pressA then pressA, pressX = pa, m end
            end
            prev = { p.spots[k][1], p.spots[k][2] }
        end
        -- move to CLEAR, then to countdown
        if t >= p.tclear - 0.5 then
            local u = easeInOut((t - (p.tclear - 0.5)) / 0.45)
            cx, cy, kind = lerp(prev[1], p.clx, u), lerp(prev[2], p.cly, u), "point"
        end
        if t >= p.tcount - 0.5 then
            local u = easeInOut((t - (p.tcount - 0.5)) / 0.4)
            cx, cy = lerp(p.clx, p.cdx, u), lerp(p.cly, p.cdy, u)
        end
        DrawCursor(p, cx, cy, kind)

        -- button press flash
        if pressA > 0 then
            p.press:Show()
            p.press:ClearAllPoints()
            p.press:SetAllPoints(p.btns[pressX])
            p.press:SetVertexColor(1, 1, 1, 0.5 * pressA)
        else
            p.press:Hide()
        end
        local ca = blip(t, p.tclear, 0.12)
        p.clear:SetBackdropColor(0.25 + 0.4 * ca, 0.06 + 0.1 * ca, 0.06, 1)

        for k = 1, 3 do
            local a = 0.4 + (k - 1) * step + 1.35
            local u = (t >= a) and math.max(0.001, clamp((t - a) / 0.45)) or 0
            local fade = 1 - clamp((t - p.tclear - 0.05) / 0.4)
            DrawGroundMarker(p.markers[k], p, p.pick[k], p.spots[k][1], p.spots[k][2], u, fade, t)
        end

        -- pull timer pop
        local ct = t - p.tcount
        if ct > 0 and ct < 2.4 then
            local n = 3 - math.floor(ct / 0.8)
            local u = (ct % 0.8) / 0.8
            p.count:Show()
            local sc = lerp(1.8, 1, easeOut(u * 2))
            p.count:SetScale(sc)
            At(p.count, p.layer, (p.W / 2) / sc, (p.H * 0.35) / sc)
            p.count:SetAlpha(1 - clamp((u - 0.6) / 0.4))
            p.count.text:SetText(n)
            p.count.text:SetTextColor(1, 0.82 - (3 - n) * 0.25, 0.2)
        else
            p.count:Hide()
        end

        DrawKey(p, nil)
        if t < p.tclear - 0.5 then
            local k = math.max(1, math.min(3, math.floor((t - 0.4) / step) + 1))
            p.caption:SetText(L["Click %s then click the ground to drop it"]:format(IconTag(p.pick[k])))
        elseif t < p.tcount - 0.5 then
            p.caption:SetText(L["|cffff6666CLEAR|r removes every ground marker"])
        else
            p.caption:SetText(L["Ready check  ·  pull timer  ·  cancel timer"])
        end
    end,
}

-- ---------- Scene: cycle order ----------
SCENES.order = {
    build = function(p)
        p.slots = {}
        for i = 1, 8 do
            local s = CreateFrame("Frame", nil, p.layer, BACKDROP_TMPL)
            s:SetSize(40, 40)
            Skin(s, { 0.08, 0.085, 0.1, 1 }, { 0.25, 0.27, 0.31, 1 })
            s.icon = s:CreateTexture(nil, "ARTWORK")
            s.icon:SetSize(26, 26); s.icon:SetPoint("CENTER")
            s.num = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            s.num:SetPoint("TOP", s, "BOTTOM", 0, -3)
            s.glow = s:CreateTexture(nil, "BACKGROUND")
            s.glow:SetTexture(CIRCLE); s.glow:SetBlendMode("ADD")
            s.glow:SetPoint("CENTER"); s.glow:SetSize(70, 70)
            p.slots[i] = s
        end
        p.arrow = p.layer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        p.arrow:SetText("v")
        p.next = p.layer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        p.next:SetText(L["NEXT"])
    end,
    refresh = function(p)
        p.order = ActiveOrder()   -- the cycler being edited
        p.n = math.min(#p.order, 8)
        if OE.which == "target" then
            p.pk, p.ck = KeyOr(TargetPlaceKey(), "KEY"), KeyOr(TargetClearKey(), "KEY")
        elseif OE.which == "mouseover" then
            p.pk, p.ck = KeyOr(MousePlaceKey(), "KEY"), KeyOr(MouseClearKey(), "KEY")
        else
            p.pk = KeyOr(WorldPlaceKey(), "B")
            p.ck = KeyOr(WorldClearKey(), "CTRL-B")
        end
        local gap = 50
        local left = p.W / 2 - (p.n - 1) * gap / 2
        p.sx = {}
        for i = 1, 8 do
            local s = p.slots[i]
            if i <= p.n then
                s:Show()
                p.sx[i] = left + (i - 1) * gap
                At(s, p.layer, p.sx[i], p.H * 0.52)
                s.icon:SetTexture(WM[p.order[i]].icon)
                s.num:SetText(i)
            else
                s:Hide()
            end
        end
        p.step = 0.55
        p.t0 = 0.5
        p.twrap = p.t0 + p.n * p.step          -- one extra press wraps to slot 1
        p.tc = p.twrap + p.step + 0.5
        p.dur = p.tc + 1.4
    end,
    update = function(p, t)
        local presses = 0
        if t >= p.t0 then presses = math.floor((t - p.t0) / p.step) + 1 end
        if t >= p.tc then presses = 0 end
        local maxPress = p.n + 1
        presses = math.min(presses, maxPress)
        local lit = math.min(presses, p.n)
        for i = 1, p.n do
            local s = p.slots[i]
            local c = WM[p.order[i]].color
            local on = i <= lit
            local a = on and clamp((t - (p.t0 + (i - 1) * p.step)) / 0.25) or 0
            if t >= p.tc then a = 1 - clamp((t - p.tc) / 0.3) end
            s.glow:SetVertexColor(c[1], c[2], c[3], 0.35 * a)
            s:SetBackdropBorderColor(lerp(0.25, c[1], a), lerp(0.27, c[2], a), lerp(0.31, c[3], a), 1)
            s.icon:SetDesaturated(a < 0.5)
            s.icon:SetAlpha(0.45 + 0.55 * a)
            local sc = 1 + 0.25 * blip(t, p.t0 + (i - 1) * p.step + 0.05, 0.12)
            s.icon:SetSize(26 * sc, 26 * sc)
        end
        -- NEXT pointer
        local nextIdx
        if t >= p.tc then nextIdx = 1
        elseif presses >= p.n then nextIdx = (presses % p.n) + 1
        else nextIdx = presses + 1 end
        local x = p.sx[nextIdx] or p.sx[1]
        p.arrow:ClearAllPoints(); p.arrow:SetPoint("BOTTOM", p.layer, "BOTTOMLEFT", x, p.H * 0.52 + 24 + math.sin(t * 6) * 2)
        p.next:ClearAllPoints(); p.next:SetPoint("BOTTOM", p.arrow, "TOP", 0, 0)

        if t < p.tc - 0.2 then
            local pr = 0
            for i = 1, maxPress do pr = math.max(pr, blip(t, p.t0 + (i - 1) * p.step + 0.05, 0.1)) end
            DrawKey(p, p.pk, pr)
            if presses > p.n then
                p.caption:SetText(L["After the last marker the cycle wraps back to slot |cffffd1001|r"])
            else
                p.caption:SetText(L["Each press of |cffffd100%s|r places the next marker in this order"]:format(p.pk))
            end
        else
            DrawKey(p, p.ck, blip(t, p.tc, 0.14))
            p.caption:SetText(L["|cffffd100%s|r  resets the cycle  ·  next press is slot |cffffd1001|r again"]:format(p.ck))
        end
        DrawCursor(p, nil)
    end,
}

-- ==========================================================
-- Popup config window
-- ==========================================================
local cfg          -- the popup
local tabs = {}    -- { button, page }
local PAGE_W = 620

local function CreatePage(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -8, 0)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(PAGE_W, 10)
    sf:SetScrollChild(child)

    local thumb = sf:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 1, 1, 0.18)
    thumb:SetWidth(3)
    local function UpdateThumb()
        local viewH, childH = sf:GetHeight(), child:GetHeight()
        if childH <= viewH + 1 or viewH <= 0 then thumb:Hide(); return end
        thumb:Show()
        local h = math.max(24, viewH * viewH / childH)
        local maxScroll = childH - viewH
        local y = (sf:GetVerticalScroll() / maxScroll) * (viewH - h)
        thumb:SetHeight(h)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 6, -y)
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d)
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - d * 45)))
        UpdateThumb()
    end)
    sf:SetScript("OnShow", UpdateThumb)
    sf:SetScript("OnSizeChanged", UpdateThumb)
    sf.child = child
    sf.UpdateThumb = UpdateThumb
    sf:Hide()
    return sf, child
end

local function PageHeader(child, title, sub)
    local t = Text(child, "GameFontNormalLarge", title, { 1, 1, 1 })
    t:SetPoint("TOPLEFT", 4, -4)
    local s = Text(child, "GameFontHighlightSmall", sub, C.dim)
    s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4)
    s:SetWidth(PAGE_W - 8)
    return -48
end

local function SelectTab(key)
    if not cfg then return end
    for k, tb in pairs(tabs) do
        local sel = (k == key)
        tb.page:SetShown(sel)
        tb.btn.selBar:SetShown(sel)
        tb.btn.bg:SetColorTexture(1, 1, 1, sel and 0.07 or 0)
        tb.btn.text:SetTextColor(sel and 1 or 0.75, sel and 0.85 or 0.76, sel and 0.3 or 0.8)
    end
    cfg.current = key
    RefreshAll()
end

-- ---------- page builders ----------
local BUILD = {}

-- status tile on the overview page
local function StatusTile(child, x, y, which, title, iconM, tabKey, keysFn)
    local tile = CreateFrame("Button", nil, child, BACKDROP_TMPL)
    tile:SetSize(302, 64)
    tile:SetPoint("TOPLEFT", x, y)
    Skin(tile, C.card, C.border)
    local ic = tile:CreateTexture(nil, "ARTWORK")
    ic:SetTexture(WM[iconM].icon); ic:SetSize(30, 30); ic:SetPoint("LEFT", 12, 0)
    local tt = Text(tile, "GameFontNormal", title, { 1, 1, 1 })
    tt:SetPoint("TOPLEFT", ic, "TOPRIGHT", 10, 2)
    local pill = CreateFrame("Frame", nil, tile, BACKDROP_TMPL)
    pill:SetSize(40, 16); pill:SetPoint("TOPRIGHT", -10, -10)
    Skin(pill, { 0, 0, 0, 1 }, { 0, 0, 0, 1 })
    pill.text = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pill.text:SetPoint("CENTER")
    local keys = Text(tile, "GameFontHighlightSmall", "", C.dim)
    keys:SetPoint("TOPLEFT", tt, "BOTTOMLEFT", 0, -6)
    keys:SetWidth(240)
    tile:SetScript("OnClick", function() SelectTab(tabKey) end)
    tile:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
    tile:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end)
    table.insert(refreshers, function()
        local on = FeatureOn(which)
        pill.text:SetText(on and L["ON"] or L["OFF"])
        pill:SetBackdropColor(on and 0.12 or 0.3, on and 0.4 or 0.08, on and 0.18 or 0.08, 1)
        pill:SetBackdropBorderColor(on and C.good[1] or C.bad[1], on and C.good[2] or C.bad[2], on and C.good[3] or C.bad[3], 1)
        keys:SetText(keysFn())
        ic:SetDesaturated(not on)
    end)
end

BUILD.overview = function(child)
    local y = PageHeader(child, "Welcome to World Marker Cycler",
        "Place raid markers with a single key. Pick a section on the left - every page has a live preview of what it does.")
    local prev = CreatePreview(child, PAGE_W, 190, "world")
    prev:SetPoint("TOPLEFT", 0, y)
    y = y - 202
    local function k(a, b) return L["Cycle: |cffffffff%s|r   Clear: |cffffffff%s|r"]:format(PrettyKey(a()), PrettyKey(b())) end
    StatusTile(child, 0,   y, "world",     "Ground Markers",    1, "world",     function() return k(WorldPlaceKey, WorldClearKey) end)
    StatusTile(child, 318, y, "target",    "Target Markers",    8, "target",    function() return k(TargetPlaceKey, TargetClearKey) end)
    y = y - 72
    StatusTile(child, 0,   y, "mouseover", "Mouseover Markers", 3, "mouseover", function() return k(MousePlaceKey, MouseClearKey) end)
    StatusTile(child, 318, y, "raid",      "Raid Marker Bar",   6, "raidbar",   function() return L["Open key: |cffffffff%s|r"]:format(PrettyKey(PickerKey())) end)
    y = y - 76
    local tip = Text(child, "GameFontHighlightSmall",
        "|cffffd100Tip:|r you must be group leader or assistant (or solo) for markers to appear. Blizzard allows about 3 marker actions per second.", C.dim)
    tip:SetPoint("TOPLEFT", 4, y)
    tip:SetWidth(PAGE_W - 8)
    y = y - 30
    return y
end

BUILD.world = function(child)
    local y = PageHeader(child, "Ground Markers",
        "Drops world markers on the ground at your mouse cursor. Each press places the next marker; the clear key removes them all.")
    local prev = CreatePreview(child, PAGE_W, 200, "world")
    prev:SetPoint("TOPLEFT", 0, y)
    y = y - 212
    local card = W.Card(child, PAGE_W, 196, "Settings")
    card:SetPoint("TOPLEFT", 0, y)
    local sw = W.Switch(card, "Enable ground marker keybinds", function() return FeatureOn("world") end,
        function(v) SetFeature("world", v) end)
    sw:SetPoint("TOPLEFT", 12, -38)
    local r1 = W.KeyRow(card, L["World Cycle Key:"], WorldPlaceKey, function(mod, key)
        if api and api.SetPlaceKey then api.SetPlaceKey(mod, key) end
    end)
    r1:SetPoint("TOPLEFT", 12, -68)
    local r2 = W.KeyRow(card, L["World Clear Key:"], WorldClearKey, function(mod, key)
        if api and api.SetClearKey then api.SetClearKey(mod, key) end
    end)
    r2:SetPoint("TOPLEFT", 12, -100)

    local el = Text(card, "GameFontHighlight", "Click edge:")
    el:SetPoint("TOPLEFT", 12, -142)
    local seg = W.Segmented(card, {
        { label = "Auto", value = "auto" }, { label = "Up", value = "up" }, { label = "Down", value = "down" },
    }, function()
        local v = WMC_Saved and WMC_Saved.useClickDown
        if v == true then return "down" elseif v == false then return "up" end
        return "auto"
    end, function(v)
        if v == "auto" then
            if SlashCmdList and SlashCmdList["WMCCLICKEDGE"] then SlashCmdList["WMCCLICKEDGE"]("auto")
            elseif WMC_Saved then WMC_Saved.useClickDown = nil end
        elseif api and api.SetUseClickDown then
            api.SetUseClickDown(v == "down")
        end
    end)
    seg:SetPoint("LEFT", el, "LEFT", 205, 0)
    local ed = Text(card, "GameFontHighlightSmall",
        "Auto detects keyboard vs mouse.  Up = keyboard keys.  Down = MMO mouse / extra mouse buttons.", C.dim)
    ed:SetPoint("TOPLEFT", 12, -166)
    ed:SetWidth(PAGE_W - 24)
    y = y - 206
    return y
end

BUILD.target = function(child)
    local y = PageHeader(child, "Target Markers",
        "Puts a raid icon over your current target. Press again on a new target to give it the next icon in your order.")
    local prev = CreatePreview(child, PAGE_W, 200, "target")
    prev:SetPoint("TOPLEFT", 0, y)
    y = y - 212
    local card = W.Card(child, PAGE_W, 136, "Settings")
    card:SetPoint("TOPLEFT", 0, y)
    local sw = W.Switch(card, "Enable target marker keybinds", function() return FeatureOn("target") end,
        function(v) SetFeature("target", v) end)
    sw:SetPoint("TOPLEFT", 12, -38)
    local function setTarget(field, mod, key)
        WMC_TargetSaved = WMC_TargetSaved or {}
        WMC_TargetSaved[field .. "Modifier"] = mod or ""
        WMC_TargetSaved[field .. "Key"] = key or ""
        local tApi = _G.WorldMarkerCyclerTargetAPI
        if tApi and tApi.UpdateBindings then tApi.UpdateBindings() end
    end
    local r1 = W.KeyRow(card, L["Target Cycle Key:"], TargetPlaceKey, function(mod, key) setTarget("place", mod, key) end)
    r1:SetPoint("TOPLEFT", 12, -68)
    local r2 = W.KeyRow(card, L["Target Clear Key:"], TargetClearKey, function(mod, key) setTarget("clear", mod, key) end)
    r2:SetPoint("TOPLEFT", 12, -100)
    y = y - 146
    return y
end

BUILD.mouseover = function(child)
    local y = PageHeader(child, "Mouseover Markers",
        "Marks the unit under your mouse (enemy or friendly) without changing target. With nothing hovered it marks your target instead.")
    local prev = CreatePreview(child, PAGE_W, 200, "mouseover")
    prev:SetPoint("TOPLEFT", 0, y)
    y = y - 212
    local card = W.Card(child, PAGE_W, 136, "Settings")
    card:SetPoint("TOPLEFT", 0, y)
    local sw = W.Switch(card, "Enable mouseover marker keybinds", function() return FeatureOn("mouseover") end,
        function(v) SetFeature("mouseover", v) end)
    sw:SetPoint("TOPLEFT", 12, -38)
    local r1 = W.KeyRow(card, L["Mouseover Cycle Key:"], MousePlaceKey, function(mod, key)
        local m = _G.WorldMarkerCyclerMouseoverAPI
        if m and m.SetPlaceKey then m.SetPlaceKey(mod, key) end
    end)
    r1:SetPoint("TOPLEFT", 12, -68)
    local r2 = W.KeyRow(card, L["Mouseover Clear Key:"], MouseClearKey, function(mod, key)
        local m = _G.WorldMarkerCyclerMouseoverAPI
        if m and m.SetClearKey then m.SetClearKey(mod, key) end
    end)
    r2:SetPoint("TOPLEFT", 12, -100)
    y = y - 146
    return y
end

local function ApplyOrder(t)
    local s, k = OrderStore()
    s[k] = t
    if OE.which == "world" and api and api.SetOrder then api.SetOrder(t) end
    SyncOrders()
    RefreshAll()
end

local function ApplyCustom(list)
    local s = OrderStore()
    s.customCycleMarkers = list
    if OE.which == "world" and api and api.SetCustomCycleMarkers then api.SetCustomCycleMarkers(list) end
    SyncOrders()
    RefreshAll()
end

BUILD.order = function(child)
    local y = PageHeader(child, "Cycle Order",
        "Ground markers, target and mouseover each have their own cycle order. Pick which one to edit. After a clear, the cycle restarts at slot 1.")
    -- which cycler this page edits
    local el = Text(child, "GameFontNormal", "Editing:", C.accent)
    el:SetPoint("TOPLEFT", 0, y - 4)
    local pick = W.Segmented(child, {
            { label = "Ground markers", value = "world" },
            { label = "Target", value = "target" },
            { label = "Mouseover", value = "mouseover" },
        },
        function() return OE.which end,
        function(v)
            OE.which = v
            if OE.prev then OE.prev.dur = nil end   -- restart the preview with this order
        end, 130)
    pick:SetPoint("LEFT", el, "RIGHT", 10, 0)
    y = y - 32
    local prev = CreatePreview(child, PAGE_W, 150, "order")
    prev:SetPoint("TOPLEFT", 0, y)
    OE.prev = prev
    y = y - 162

    -- full order editor
    local card = W.Card(child, PAGE_W, 150, "Full order  |cff888888(click two slots to swap them)|r")
    card:SetPoint("TOPLEFT", 0, y)
    local slots, selected = {}, nil
    for i = 1, 8 do
        local s = CreateFrame("Button", nil, card, BACKDROP_TMPL)
        s:SetSize(52, 52)
        s:SetPoint("TOPLEFT", 12 + (i - 1) * 60, -40)
        Skin(s, { 0.05, 0.055, 0.07, 1 }, { 0.28, 0.3, 0.34, 1 })
        s.icon = s:CreateTexture(nil, "ARTWORK"); s.icon:SetSize(34, 34); s.icon:SetPoint("CENTER")
        s.num = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        s.num:SetPoint("TOPLEFT", 3, -3); s.num:SetText(i)
        s:SetScript("OnClick", function()
            if not selected then
                selected = i
            else
                if selected ~= i then
                    local t = {}
                    for j, v in ipairs(FullOrder()) do t[j] = v end
                    t[selected], t[i] = t[i], t[selected]
                    selected = nil
                    ApplyOrder(t)
                    return
                end
                selected = nil
            end
            RefreshAll()
        end)
        s:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Slot %s: %s"]:format(tostring(i), MarkerText(FullOrder()[i])))
            GameTooltip:AddLine(L["Click, then click another slot to swap."], 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        s:SetScript("OnLeave", function() GameTooltip:Hide() end)
        slots[i] = s
    end
    local ol = Text(card, "GameFontHighlightSmall", "Or type it:", C.dim)
    ol:SetPoint("TOPLEFT", 12, -108)
    local box = W.EditBox(card, 150)
    box:SetPoint("LEFT", ol, "RIGHT", 8, 0)
    local function applyBox()
        local t = {}
        for num in string.gmatch(box:GetText(), "%d") do
            local n = tonumber(num)
            if n >= 1 and n <= 8 then table.insert(t, n) end
        end
        if #t == 8 then ApplyOrder(t) else RefreshAll() end
    end
    box:SetScript("OnEnterPressed", function(self) applyBox(); self:ClearFocus() end)
    box:HookScript("OnEditFocusLost", applyBox)
    local reset = W.Button(card, 110, 22, "Reset default", function() ApplyOrder({ 6, 4, 3, 7, 1, 2, 5, 8 }) end)
    reset:SetPoint("LEFT", box, "RIGHT", 10, 0)
    local legend = Text(card, "GameFontDisableSmall", "1 Square  2 Triangle  3 Diamond  4 Cross  5 Star  6 Circle  7 Moon  8 Skull")
    legend:SetPoint("LEFT", reset, "RIGHT", 10, 0)
    legend:SetWidth(PAGE_W - 12 - 60 - 158 - 120 - 20)
    table.insert(refreshers, function()
        local o = FullOrder()
        for i = 1, 8 do
            slots[i].icon:SetTexture(WM[o[i]].icon)
            if selected == i then
                slots[i]:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            else
                local c = WM[o[i]].color
                slots[i]:SetBackdropBorderColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1)
            end
        end
        if not box:HasFocus() then box:SetText(table.concat(o, ",")) end
    end)
    y = y - 160

    -- custom subset
    local cc = W.Card(child, PAGE_W, 170, "Custom Cycle Mode  |cff888888(only cycle a few markers)|r")
    cc:SetPoint("TOPLEFT", 0, y)
    local sw = W.Switch(cc, "Use a custom subset instead of the full order",
        function() return OrderStore().customCycleEnabled and true or false end,
        function(v)
            local s = OrderStore()
            s.customCycleEnabled = v and true or false
            if OE.which == "world" and api and api.SetCustomCycleEnabled then api.SetCustomCycleEnabled(v) end
            SyncOrders()
        end)
    sw:SetPoint("TOPLEFT", 12, -38)
    local mbtn = {}
    for i = 1, 8 do
        local b = CreateFrame("Button", nil, cc, BACKDROP_TMPL)
        b:SetSize(40, 40)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 48, -68)
        Skin(b, { 0.05, 0.055, 0.07, 1 }, { 0.28, 0.3, 0.34, 1 })
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(28, 28); b.icon:SetPoint("CENTER")
        b.icon:SetTexture(WM[i].icon)
        b.pos = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.pos:SetPoint("BOTTOMRIGHT", -2, 2)
        b:SetScript("OnClick", function()
            local list = {}
            local cur = CustomList()
            local found = false
            for _, m in ipairs(cur) do if m == i then found = true else table.insert(list, m) end end
            if not found then table.insert(list, i) end
            if #list == 0 then
                print(L["|cffff4444World Marker Cycler: keep at least one marker in the custom cycle.|r"])
                return
            end
            ApplyCustom(list)
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(MarkerText(i))
            GameTooltip:AddLine(L["Click to add / remove. New markers go to the end."], 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        mbtn[i] = b
    end
    local cl = Text(cc, "GameFontHighlightSmall", "Order:", C.dim)
    cl:SetPoint("TOPLEFT", 12, -124)
    local cbox = W.EditBox(cc, 150)
    cbox:SetPoint("LEFT", cl, "RIGHT", 8, 0)
    local function applyC()
        local t, seen = {}, {}
        for num in string.gmatch(cbox:GetText(), "%d") do
            local n = tonumber(num)
            if n >= 1 and n <= 8 and not seen[n] then table.insert(t, n); seen[n] = true end
        end
        if #t > 0 then ApplyCustom(t) else RefreshAll() end
    end
    cbox:SetScript("OnEnterPressed", function(self) applyC(); self:ClearFocus() end)
    cbox:HookScript("OnEditFocusLost", applyC)
    local status = Text(cc, "GameFontHighlightSmall", "")
    status:SetPoint("LEFT", cbox, "RIGHT", 12, 0)
    status:SetWidth(PAGE_W - 250)
    table.insert(refreshers, function()
        local list = CustomList()
        local enabled = OrderStore().customCycleEnabled
        local posOf = {}
        for p2, m in ipairs(list) do posOf[m] = p2 end
        for i = 1, 8 do
            local on = posOf[i] ~= nil
            mbtn[i].icon:SetDesaturated(not on)
            mbtn[i].icon:SetAlpha(on and 1 or 0.35)
            mbtn[i].pos:SetText(on and posOf[i] or "")
            local c = WM[i].color
            if on then mbtn[i]:SetBackdropBorderColor(c[1], c[2], c[3], 1)
            else mbtn[i]:SetBackdropBorderColor(0.28, 0.3, 0.34, 1) end
        end
        if not cbox:HasFocus() then cbox:SetText(table.concat(list, ",")) end
        if enabled then
            local s = ""
            for _, m in ipairs(list) do s = s .. IconTag(m, 12) .. " " end
            status:SetText(L["|cff4de680Active:|r %s"]:format(s))
        else
            status:SetText(L["|cff888888Off - using the full 8-marker order|r"])
        end
    end)
    y = y - 180
    return y
end

BUILD.raidbar = function(child)
    local y = PageHeader(child, "Raid Marker Bar",
        "A small bar with every ground marker, CLEAR, ready check and pull-timer buttons. Click a marker, then click the ground.")
    local prev = CreatePreview(child, PAGE_W, 200, "raidbar")
    prev:SetPoint("TOPLEFT", 0, y)
    y = y - 212
    local card = W.Card(child, PAGE_W, 196, "Settings")
    card:SetPoint("TOPLEFT", 0, y)
    local rApi = function() return _G.WorldMarkerCyclerRaidPickerAPI end
    local sw = W.Switch(card, "Enable the open-bar keybind", function() return FeatureOn("raid") end,
        function(v) SetFeature("raid", v) end)
    sw:SetPoint("TOPLEFT", 12, -38)
    local r1 = W.KeyRow(card, L["Raid Picker Open Key:"], PickerKey, function(mod, key)
        local a = rApi()
        if a and a.SetOpenKey then a.SetOpenKey(mod, key)
        else
            WMC_RaidPickerSaved = WMC_RaidPickerSaved or {}
            WMC_RaidPickerSaved.openModifier = mod or ""
            WMC_RaidPickerSaved.openKey = key or ""
        end
    end)
    r1:SetPoint("TOPLEFT", 12, -68)
    local rows = W.Switch(card, L["Marker bar: two rows"], function()
        local a = rApi()
        local r = (a and a.GetRows and a.GetRows()) or (WMC_RaidPickerSaved and WMC_RaidPickerSaved.rows) or 1
        return r == 2
    end, function(v)
        local want = v and 2 or 1
        local a = rApi()
        if a and a.SetRows then
            if not a.SetRows(want) then print(L["Marker bar layout will change when you leave combat."]) end
        else
            WMC_RaidPickerSaved = WMC_RaidPickerSaved or {}
            WMC_RaidPickerSaved.rows = want
        end
    end, L["Splits the bar so the markers sit above the action buttons."])
    rows:SetPoint("TOPLEFT", 12, -104)
    local show = W.Button(card, 130, 24, "Show / Hide bar", function()
        local a = rApi(); if a and a.Toggle then a.Toggle() end
    end, true)
    show:SetPoint("TOPLEFT", 12, -154)
    local lock = W.Button(card, 130, 24, "Lock / Unlock", function()
        local a = rApi(); if a and a.ToggleLock then a.ToggleLock() end
        RefreshAll()
    end)
    lock:SetPoint("LEFT", show, "RIGHT", 8, 0)
    local lockState = Text(card, "GameFontHighlightSmall", "", C.dim)
    lockState:SetPoint("LEFT", lock, "RIGHT", 10, 0)
    table.insert(refreshers, function()
        local a = rApi()
        local locked = a and a.IsLocked and a.IsLocked()
        lockState:SetText(locked and L["Bar is |cffffd100locked|r"] or L["Bar is |cff4de680unlocked|r - drag to move, right-click to lock"])
    end)
    y = y - 206
    return y
end

BUILD.help = function(child)
    local y = PageHeader(child, "Help & Commands", "Slash commands, mouse button names and good-to-know limits.")
    local card = W.Card(child, PAGE_W, 235, "Slash commands")
    card:SetPoint("TOPLEFT", 0, y)
    local cmds = {
        { "/wmc", "Open this window" },
        { "/wmcstatus", "Print your current keys and order" },
        { "/wmcclear", "Clear all override keybinds and reset the cycle" },
        { "/wmcclickedge auto|up|down", "Change the click edge for the cycle key" },
        { "/wmcrshow  /wmcrhide  /wmcrtoggle", "Show / hide the raid marker bar" },
        { "/wmcrlock", "Lock or unlock the raid marker bar" },
        { "/wmcrrows", "Toggle one or two rows on the bar" },
        { "/wmcpull <1-60>", "Set how many seconds the pull-timer button counts" },
        { "/wmcmadd  /wmctadd", "Old key commands - the menu does this for you now" },
    }
    for i, c in ipairs(cmds) do
        local a = Text(card, "GameFontNormal", c[1])
        a:SetPoint("TOPLEFT", 12, -38 - (i - 1) * 21)
        local b = Text(card, "GameFontHighlightSmall", c[2], C.dim)
        b:SetPoint("TOPLEFT", 270, -40 - (i - 1) * 21)
    end
    y = y - 245

    local mc = W.Card(child, PAGE_W, 150, "Mouse button names")
    mc:SetPoint("TOPLEFT", 0, y)
    local mouseKeys = {
        { "MOUSEWHEELUP", "Wheel up" }, { "MOUSEWHEELDOWN", "Wheel down" }, { "BUTTON3", "Middle button" },
        { "BUTTON4", "Side button 4" }, { "BUTTON5", "Side button 5" }, { "BUTTON6-7", "Extra buttons" },
    }
    for i, m in ipairs(mouseKeys) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local a = Text(mc, "GameFontNormal", m[1])
        a:SetPoint("TOPLEFT", 12 + col * 300, -38 - row * 22)
        local b = Text(mc, "GameFontHighlightSmall", m[2], C.dim)
        b:SetPoint("TOPLEFT", 160 + col * 300, -40 - row * 22)
    end
    local ex = Text(mc, "GameFontHighlightSmall",
        "Combine with |cffffd100CTRL-|r, |cffffd100ALT-|r or |cffffd100SHIFT-|r, e.g. |cffffd100CTRL-MOUSEWHEELDOWN|r. The easiest way is just clicking a key box and pressing the combo.", C.dim)
    ex:SetPoint("TOPLEFT", 12, -110)
    ex:SetWidth(PAGE_W - 24)
    y = y - 160

    local warn = CreateFrame("Frame", nil, child, BACKDROP_TMPL)
    warn:SetSize(PAGE_W, 58)
    warn:SetPoint("TOPLEFT", 0, y)
    Skin(warn, { 0.16, 0.05, 0.05, 0.95 }, { 0.8, 0.2, 0.2, 1 })
    local wt = Text(warn, "GameFontHighlight",
        "|cffff6666Blizzard limit:|r about 3 world marker actions per second. Extra presses are ignored, so this addon throttles for you. Keybinds set here override bindings made with slash commands.")
    wt:SetPoint("TOPLEFT", 10, -9); wt:SetWidth(PAGE_W - 20)
    y = y - 68
    return y
end

local TAB_LIST = {
    { key = "overview",  label = "Overview",       icon = 8 },
    { key = "world",     label = "Ground Markers", icon = 1 },
    { key = "target",    label = "Target",         icon = 4 },
    { key = "mouseover", label = "Mouseover",      icon = 3 },
    { key = "order",     label = "Cycle Order",    icon = 5 },
    { key = "raidbar",   label = "Raid Bar",       icon = 6 },
    { key = "help",      label = "Help",           icon = 7 },
}

local function GetVersion()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = getMeta and getMeta("WorldMarkerCycler", "Version")
    return v and ("v" .. v) or ""
end

local function BuildConfig()
    cfg = CreateFrame("Frame", "WMC_ConfigFrame", UIParent, BACKDROP_TMPL)
    cfg:SetSize(840, 580)
    cfg:SetPoint("CENTER")
    cfg:SetFrameStrata("DIALOG")
    cfg:SetToplevel(true)
    cfg:SetClampedToScreen(true)
    cfg:SetMovable(true)
    cfg:EnableMouse(true)
    Skin(cfg, C.bg, { 0.30, 0.27, 0.18, 1 })
    tinsert(UISpecialFrames, "WMC_ConfigFrame")   -- ESC closes

    -- header
    local header = CreateFrame("Frame", nil, cfg)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(46)
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    SetGrad(hbg, "HORIZONTAL", 0.20, 0.15, 0.05, 1, 0.06, 0.065, 0.08, 1)
    local hline = header:CreateTexture(nil, "ARTWORK")
    hline:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.45)
    hline:SetHeight(1)
    hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT")
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() cfg:StartMoving() end)
    header:SetScript("OnDragStop", function() cfg:StopMovingOrSizing() end)

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(WM[8].icon); logo:SetSize(30, 30); logo:SetPoint("LEFT", 12, 0)
    -- gentle spin-in glow behind the logo
    local lglow = header:CreateTexture(nil, "BORDER")
    lglow:SetTexture(SPARK); lglow:SetBlendMode("ADD"); lglow:SetSize(56, 56)
    lglow:SetPoint("CENTER", logo, "CENTER"); lglow:SetVertexColor(1, 0.8, 0.3, 0.5)
    header:SetScript("OnUpdate", function()
        lglow:SetAlpha(0.35 + 0.25 * math.sin(GetTime() * 2))
    end)
    local title = Text(header, "GameFontNormalLarge", "World Marker Cycler")
    title:SetPoint("LEFT", logo, "RIGHT", 10, 6)
    local ver = Text(header, "GameFontHighlightSmall", GetVersion() .. "   |cff888888" .. L["by CKRAIGFRIEND"] .. "|r", C.dim)
    ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("RIGHT", -6, 0)
    close:SetScript("OnClick", function() cfg:Hide() end)

    -- sidebar
    local side = CreateFrame("Frame", nil, cfg, BACKDROP_TMPL)
    side:SetPoint("TOPLEFT", 1, -47)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(180)
    Skin(side, C.side, { 0, 0, 0, 0 })
    local sline = side:CreateTexture(nil, "ARTWORK")
    sline:SetColorTexture(1, 1, 1, 0.06); sline:SetWidth(1)
    sline:SetPoint("TOPRIGHT"); sline:SetPoint("BOTTOMRIGHT")

    -- content area
    local content = CreateFrame("Frame", nil, cfg)
    content:SetPoint("TOPLEFT", side, "TOPRIGHT", 18, -14)
    content:SetPoint("BOTTOMRIGHT", -12, 12)

    for i, info in ipairs(TAB_LIST) do
        local b = CreateFrame("Button", nil, side)
        b:SetSize(178, 34)
        b:SetPoint("TOPLEFT", 0, -10 - (i - 1) * 36)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints(); b.bg:SetColorTexture(1, 1, 1, 0)
        b.selBar = b:CreateTexture(nil, "ARTWORK")
        b.selBar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        b.selBar:SetWidth(3); b.selBar:SetPoint("TOPLEFT"); b.selBar:SetPoint("BOTTOMLEFT")
        b.selBar:Hide()
        local ic = b:CreateTexture(nil, "ARTWORK")
        ic:SetTexture(WM[info.icon].icon); ic:SetSize(18, 18); ic:SetPoint("LEFT", 16, 0)
        b.text = Text(b, "GameFontHighlight", info.label)
        b.text:SetPoint("LEFT", ic, "RIGHT", 10, 0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.04)
        b:SetScript("OnClick", function() SelectTab(info.key) end)

        local page, child = CreatePage(content)
        local h = BUILD[info.key](child)
        child:SetHeight(math.abs(h) + 10)
        tabs[info.key] = { btn = b, page = page }
    end

    -- sidebar footer
    local foot = Text(side, "GameFontDisableSmall", "/wmc to open\nESC to close\n\nPreviews use your\nlive settings.")
    foot:SetPoint("BOTTOMLEFT", 16, 14)

    -- open animation: quick fade + rise
    cfg.anim = 0
    cfg:SetScript("OnShow", function(self)
        self.anim = 0
        self:SetAlpha(0)
        RefreshAll()
    end)
    cfg:SetScript("OnUpdate", function(self, el)
        if self.anim < 1 then
            self.anim = math.min(1, self.anim + el * 5)
            local e = easeOut(self.anim)
            self:SetAlpha(e)
        end
    end)
    cfg:Hide()
    SelectTab("overview")
end

local function OpenConfig(tabKey)
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
    if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() and HideUIPanel then HideUIPanel(InterfaceOptionsFrame) end
    if not cfg then BuildConfig() end
    cfg:Show()
    SelectTab(tabKey or cfg.current or "overview")
end

local function ToggleConfig()
    if cfg and cfg:IsShown() then cfg:Hide() else OpenConfig() end
end

-- public
WorldMarkerCyclerUIAPI = WorldMarkerCyclerUIAPI or {}
WorldMarkerCyclerUIAPI.Open = OpenConfig
WorldMarkerCyclerUIAPI.Toggle = ToggleConfig

SLASH_WMCCONFIG1 = "/wmc"
SLASH_WMCCONFIG2 = "/wmcconfig"
SlashCmdList["WMCCONFIG"] = function() ToggleConfig() end

-- ==========================================================
-- Slim launcher page in Blizzard's AddOns settings
-- ==========================================================
local function BuildUI()
    f = CreateFrame("Frame", "WorldMarkerCyclerUI", InterfaceOptionsFramePanelContainer)
    f.name = "World Marker Cycler"
    if SettingsPanel and SettingsPanel.AddCategory then
        SettingsPanel.AddCategory(f)
    elseif Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(f, f.name)
        Settings.RegisterAddOnCategory(category)
        f.categoryID = category and category.GetID and category:GetID()
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(f)
    end

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(WM[8].icon); logo:SetSize(40, 40); logo:SetPoint("TOPLEFT", 16, -16)
    local title = Text(f, "GameFontNormalHuge", "World Marker Cycler")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)
    local sub = Text(f, "GameFontHighlight", GetVersion() .. "  ·  " .. L["one-key raid markers for ground, target and mouseover"], C.dim)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    local open = W.Button(f, 260, 34, "Open World Marker Cycler", function() OpenConfig() end, true)
    open:SetPoint("TOPLEFT", 16, -78)
    local hint = Text(f, "GameFontHighlightSmall", "or type |cffffd100/wmc|r in chat", C.dim)
    hint:SetPoint("LEFT", open, "RIGHT", 12, 0)

    local prev = CreatePreview(f, 560, 170, "world")
    prev:SetPoint("TOPLEFT", 16, -126)

    local qt = Text(f, "GameFontNormal", "Quick toggles", C.accent)
    qt:SetPoint("TOPLEFT", 16, -312)
    local items = {
        { "world", "Ground markers" }, { "target", "Target markers" },
        { "mouseover", "Mouseover markers" }, { "raid", "Raid bar keybind" },
    }
    for i, it in ipairs(items) do
        local sw = W.Switch(f, it[2], function() return FeatureOn(it[1]) end, function(v) SetFeature(it[1], v) end)
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        sw:SetPoint("TOPLEFT", 16 + col * 280, -336 - row * 30)
    end

    f:SetScript("OnShow", RefreshAll)
    f:Hide()

    -- keep the old command working
    SLASH_WMCEDITOR1 = "/wmckey"
    SlashCmdList["WMCEDITOR"] = function() ToggleConfig() end
end

function WorldMarkerCyclerUI_OnReady()
    if not f then BuildUI() end
end

-- ==========================================================
-- One-time setup popup
-- ==========================================================
local function HasMissingKeybinds()
    if FeatureOn("world") and WMC_Saved then
        if WorldPlaceKey() == "" or WorldClearKey() == "" then return true end
    end
    if FeatureOn("target") then
        if not WMC_TargetSaved or TargetPlaceKey() == "" or TargetClearKey() == "" then return true end
    end
    if FeatureOn("mouseover") then
        if not WMC_MouseoverSaved or MousePlaceKey() == "" or MouseClearKey() == "" then return true end
    end
    if FeatureOn("raid") then
        if not WMC_RaidPickerSaved or PickerKey() == "" then return true end
    end
    return false
end

local setupPopup
local function ShowSetupPopup()
    if setupPopup then setupPopup:Show(); return end
    setupPopup = CreateFrame("Frame", "WMC_SetupPopup", UIParent, BACKDROP_TMPL)
    setupPopup:SetSize(460, 170)
    setupPopup:SetPoint("TOP", UIParent, "TOP", 0, -120)
    setupPopup:SetFrameStrata("DIALOG")
    Skin(setupPopup, C.bg, { C.accent[1], C.accent[2], C.accent[3], 0.8 })
    setupPopup:SetMovable(true)
    setupPopup:EnableMouse(true)
    setupPopup:RegisterForDrag("LeftButton")
    setupPopup:SetScript("OnDragStart", function(self) self:StartMoving() end)
    setupPopup:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local icon = setupPopup:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40); icon:SetPoint("TOPLEFT", 16, -16)
    icon:SetTexture(WM[8].icon)
    local title = Text(setupPopup, "GameFontNormalLarge", "World Marker Cycler")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    local body = Text(setupPopup, "GameFontHighlight",
        "Some features are enabled but don't have keybinds yet.\nOpen the settings to set them, or turn off what you don't use.")
    body:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
    body:SetPoint("RIGHT", setupPopup, "RIGHT", -16, 0)

    local openBtn = W.Button(setupPopup, 150, 26, "Open settings", function()
        setupPopup:Hide(); OpenConfig("overview")
    end, true)
    openBtn:SetPoint("BOTTOMLEFT", 16, 14)
    local dismissBtn = W.Button(setupPopup, 150, 26, "Don't show again", function()
        WMC_Saved = WMC_Saved or {}
        WMC_Saved.setupPopupDismissed = true
        setupPopup:Hide()
    end)
    dismissBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    local closeBtn = CreateFrame("Button", nil, setupPopup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() setupPopup:Hide() end)
    setupPopup:Show()
end

local popupLoader = CreateFrame("Frame")
popupLoader:RegisterEvent("PLAYER_LOGIN")
popupLoader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(3, function()
        if WMC_Saved and WMC_Saved.setupPopupDismissed then return end
        if HasMissingKeybinds() then ShowSetupPopup() end
    end)
end)
