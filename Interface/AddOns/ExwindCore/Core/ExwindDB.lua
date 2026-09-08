-- ExwindDB.lua - 全局共享数据库
-- 提供职业、专精等静态数据，减少API调用，供所有模块使用
-- TEST
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

-- 创建全局数据库表
local EXDB = {}
_G.EXDB = EXDB

-------------------------------------------------------
-- 职业数据
-------------------------------------------------------
EXDB.Classes = {
    [1]  = { id = 1, name = "战士", nameEN = "WARRIOR", colorHex = "C79C6E", colorRGB = { 198, 155, 109 }, icon = 626003, names = { ["zhCN"] = "战士", ["zhTW"] = "戰士", ["enUS"] = "Warrior", ["koKR"] = "전사", ["deDE"] = "Krieger", ["esES"] = "Guerrero", ["esMX"] = "Guerrero", ["itIT"] = "Guerriero", ["ptBR"] = "Guerreiro", ["frFR"] = "Guerrier", ["ruRU"] = "Воин" } },
    [2]  = { id = 2, name = "圣骑士", nameEN = "PALADIN", colorHex = "F48CBA", colorRGB = { 244, 140, 186 }, icon = 626000, names = { ["zhCN"] = "圣骑士", ["zhTW"] = "聖騎士", ["enUS"] = "Paladin", ["koKR"] = "성기사", ["deDE"] = "Paladin", ["esES"] = "Paladín", ["esMX"] = "Paladín", ["itIT"] = "Paladino", ["ptBR"] = "Paladino", ["frFR"] = "Paladin", ["ruRU"] = "Паладин" } },
    [3]  = { id = 3, name = "猎人", nameEN = "HUNTER", colorHex = "ABD473", colorRGB = { 170, 211, 114 }, icon = 626008, names = { ["zhCN"] = "猎人", ["zhTW"] = "獵人", ["enUS"] = "Hunter", ["koKR"] = "사냥꾼", ["deDE"] = "Jäger", ["esES"] = "Cazador", ["esMX"] = "Cazador", ["itIT"] = "Cacciatore", ["ptBR"] = "Caçador", ["frFR"] = "Chasseur", ["ruRU"] = "Охотник" } },
    [4]  = { id = 4, name = "潜行者", nameEN = "ROGUE", colorHex = "FFF468", colorRGB = { 255, 244, 104 }, icon = 626005, names = { ["zhCN"] = "潜行者", ["zhTW"] = "盜賊", ["enUS"] = "Rogue", ["koKR"] = "도적", ["deDE"] = "Schurke", ["esES"] = "Pícaro", ["esMX"] = "Pícaro", ["itIT"] = "Ladro", ["ptBR"] = "Ladino", ["frFR"] = "Voleur", ["ruRU"] = "Разбойник" } },
    [5]  = { id = 5, name = "牧师", nameEN = "PRIEST", colorHex = "FFFFFF", colorRGB = { 255, 255, 255 }, icon = 626004, names = { ["zhCN"] = "牧师", ["zhTW"] = "牧師", ["enUS"] = "Priest", ["koKR"] = "사제", ["deDE"] = "Priester", ["esES"] = "Sacerdote", ["esMX"] = "Sacerdote", ["itIT"] = "Sacerdote", ["ptBR"] = "Sacerdote", ["frFR"] = "Prêtre", ["ruRU"] = "Жрец" } },
    [6]  = { id = 6, name = "死亡骑士", nameEN = "DEATHKNIGHT", colorHex = "C41E3A", colorRGB = { 196, 30, 58 }, icon = 135771, names = { ["zhCN"] = "死亡骑士", ["zhTW"] = "死亡騎士", ["enUS"] = "Death Knight", ["koKR"] = "죽음의 기사", ["deDE"] = "Todesritter", ["esES"] = "Caballero de la Muerte", ["esMX"] = "Caballero de la Muerte", ["itIT"] = "Cavaliere della Morte", ["ptBR"] = "Cavaleiro da Morte", ["frFR"] = "Chevalier de la mort", ["ruRU"] = "Рыцарь смерти" } },
    [7]  = { id = 7, name = "萨满祭司", nameEN = "SHAMAN", colorHex = "0070DD", colorRGB = { 0, 112, 221 }, icon = 626006, names = { ["zhCN"] = "萨满祭司", ["zhTW"] = "薩滿", ["enUS"] = "Shaman", ["koKR"] = "주술사", ["deDE"] = "Schamane", ["esES"] = "Chamán", ["esMX"] = "Chamán", ["itIT"] = "Sciamano", ["ptBR"] = "Xamã", ["frFR"] = "Chaman", ["ruRU"] = "Шаман" } },
    [8]  = { id = 8, name = "法师", nameEN = "MAGE", colorHex = "3FC7EB", colorRGB = { 63, 199, 235 }, icon = 626001, names = { ["zhCN"] = "法师", ["zhTW"] = "法師", ["enUS"] = "Mage", ["koKR"] = "마법사", ["deDE"] = "Magier", ["esES"] = "Mago", ["esMX"] = "Mago", ["itIT"] = "Mago", ["ptBR"] = "Mago", ["frFR"] = "Mage", ["ruRU"] = "Маг" } },
    [9]  = { id = 9, name = "术士", nameEN = "WARLOCK", colorHex = "8788EE", colorRGB = { 135, 136, 238 }, icon = 626007, names = { ["zhCN"] = "术士", ["zhTW"] = "術士", ["enUS"] = "Warlock", ["koKR"] = "흑마법사", ["deDE"] = "Hexenmeister", ["esES"] = "Brujo", ["esMX"] = "Brujo", ["itIT"] = "Stregone", ["ptBR"] = "Bruxo", ["frFR"] = "Démoniste", ["ruRU"] = "Чернокнижник" } },
    [10] = { id = 10, name = "武僧", nameEN = "MONK", colorHex = "00FF98", colorRGB = { 0, 255, 152 }, icon = 626002, names = { ["zhCN"] = "武僧", ["zhTW"] = "武僧", ["enUS"] = "Monk", ["koKR"] = "수도사", ["deDE"] = "Mönch", ["esES"] = "Monje", ["esMX"] = "Monje", ["itIT"] = "Monaco", ["ptBR"] = "Monge", ["frFR"] = "Moine", ["ruRU"] = "Монах" } },
    [11] = { id = 11, name = "德鲁伊", nameEN = "DRUID", colorHex = "FF7C0A", colorRGB = { 255, 124, 10 }, icon = 625999, names = { ["zhCN"] = "德鲁伊", ["zhTW"] = "德魯伊", ["enUS"] = "Druid", ["koKR"] = "드루이드", ["deDE"] = "Druide", ["esES"] = "Druida", ["esMX"] = "Druida", ["itIT"] = "Druido", ["ptBR"] = "Druida", ["frFR"] = "Druide", ["ruRU"] = "Друид" } },
    [12] = { id = 12, name = "恶魔猎手", nameEN = "DEMONHUNTER", colorHex = "A330C9", colorRGB = { 163, 48, 201 }, icon = 1260827, names = { ["zhCN"] = "恶魔猎手", ["zhTW"] = "惡魔獵人", ["enUS"] = "Demon Hunter", ["koKR"] = "악마사냥꾼", ["deDE"] = "Dämonenjäger", ["esES"] = "Cazador de demonios", ["esMX"] = "Cazador de demonios", ["itIT"] = "Cacciatore di Demoni", ["ptBR"] = "Caçador de Demônios", ["frFR"] = "Chasseur de démons", ["ruRU"] = "Охотник на демонов" } },
    [13] = { id = 13, name = "唤魔师", nameEN = "EVOKER", colorHex = "33937F", colorRGB = { 51, 147, 127 }, icon = 4574311, names = { ["zhCN"] = "唤魔师", ["zhTW"] = "喚能師", ["enUS"] = "Evoker", ["koKR"] = "기원사", ["deDE"] = "Rufer", ["esES"] = "Evocador", ["esMX"] = "Evocador", ["itIT"] = "Evocatore", ["ptBR"] = "Conjurante", ["frFR"] = "Évocateur", ["ruRU"] = "Пробудитель" } },
}

-------------------------------------------------------
-- 专精数据
-------------------------------------------------------
EXDB.Specs = {
    -- 法师 (8) - 智力
    { id = 62, name = "奥术", classID = 8, icon = 135932, role = "DAMAGER", primaryStat = "智力", RangeSpell = 30451, names = { ["zhCN"] = "奥术", ["zhTW"] = "秘法", ["enUS"] = "Arcane", ["koKR"] = "비전", ["deDE"] = "Arkan", ["esES"] = "Arcano", ["esMX"] = "Arcano", ["itIT"] = "Arcano", ["ptBR"] = "Arcano", ["frFR"] = "Arcanes", ["ruRU"] = "Тайная магия" } }, --奥冲
    { id = 63, name = "火焰", classID = 8, icon = 135810, role = "DAMAGER", primaryStat = "智力", RangeSpell = 133, names = { ["zhCN"] = "火焰", ["zhTW"] = "火焰", ["enUS"] = "Fire", ["koKR"] = "화염", ["deDE"] = "Feuer", ["esES"] = "Fuego", ["esMX"] = "Fuego", ["itIT"] = "Fuoco", ["ptBR"] = "Fogo", ["frFR"] = "Feu", ["ruRU"] = "Огонь" } }, --火球
    { id = 64, name = "冰霜", classID = 8, icon = 135846, role = "DAMAGER", primaryStat = "智力", RangeSpell = 30455, names = { ["zhCN"] = "冰霜", ["zhTW"] = "冰霜", ["enUS"] = "Frost", ["koKR"] = "냉기", ["deDE"] = "Frost", ["esES"] = "Escarcha", ["esMX"] = "Escarcha", ["itIT"] = "Gelo", ["ptBR"] = "Gélido", ["frFR"] = "Givre", ["ruRU"] = "Лед" } }, --冰枪

    -- 圣骑士 (2) - 力量/智力
    { id = 65, name = "神圣", classID = 2, icon = 135920, role = "HEALER", primaryStat = "智力", RangeSpell = 275773, names = { ["zhCN"] = "神圣", ["zhTW"] = "神聖", ["enUS"] = "Holy", ["koKR"] = "신성", ["deDE"] = "Heilig", ["esES"] = "Sagrado", ["esMX"] = "Sagrado", ["itIT"] = "Sacro", ["ptBR"] = "Sagrado", ["frFR"] = "Sacré", ["ruRU"] = "Свет" } }, --审判
    { id = 66, name = "防护", classID = 2, icon = 236264, role = "TANK", primaryStat = "力量", RangeSpell = 96231, names = { ["zhCN"] = "防护", ["zhTW"] = "防護", ["enUS"] = "Protection", ["koKR"] = "보호", ["deDE"] = "Schutz", ["esES"] = "Protección", ["esMX"] = "Protección", ["itIT"] = "Protezione", ["ptBR"] = "Proteção", ["frFR"] = "Protection", ["ruRU"] = "Защита" } }, --责难
    { id = 70, name = "惩戒", classID = 2, icon = 135873, role = "DAMAGER", primaryStat = "力量", RangeSpell = 383328, names = { ["zhCN"] = "惩戒", ["zhTW"] = "懲戒", ["enUS"] = "Retribution", ["koKR"] = "징벌", ["deDE"] = "Vergeltung", ["esES"] = "Reprensión", ["esMX"] = "Reprensión", ["itIT"] = "Castigo", ["ptBR"] = "Retribuição", ["frFR"] = "Vindicte", ["ruRU"] = "Воздаяние" } }, --裁决

    -- 战士 (1) - 力量
    { id = 71, name = "武器", classID = 1, icon = 132355, role = "DAMAGER", primaryStat = "力量", RangeSpell = 12294, names = { ["zhCN"] = "武器", ["zhTW"] = "武器", ["enUS"] = "Arms", ["koKR"] = "무기", ["deDE"] = "Waffen", ["esES"] = "Armas", ["esMX"] = "Armas", ["itIT"] = "Armi", ["ptBR"] = "Armas", ["frFR"] = "Armes", ["ruRU"] = "Оружие" } }, --致死
    { id = 72, name = "狂怒", classID = 1, icon = 132347, role = "DAMAGER", primaryStat = "力量", RangeSpell = 23881, names = { ["zhCN"] = "狂怒", ["zhTW"] = "狂怒", ["enUS"] = "Fury", ["koKR"] = "분노", ["deDE"] = "Furor", ["esES"] = "Furia", ["esMX"] = "Furia", ["itIT"] = "Furia", ["ptBR"] = "Fúria", ["frFR"] = "Fureur", ["ruRU"] = "Неистовство" } }, --嗜血
    { id = 73, name = "防护", classID = 1, icon = 132341, role = "TANK", primaryStat = "力量", RangeSpell = 23922, names = { ["zhCN"] = "防护", ["zhTW"] = "防護", ["enUS"] = "Protection", ["koKR"] = "방어", ["deDE"] = "Schutz", ["esES"] = "Protección", ["esMX"] = "Protección", ["itIT"] = "Protezione", ["ptBR"] = "Proteção", ["frFR"] = "Protection", ["ruRU"] = "Защита" } }, --盾猛

    -- 德鲁伊 (11) - 敏捷/智力
    { id = 102, name = "平衡", classID = 11, icon = 136096, role = "DAMAGER", primaryStat = "智力", RangeSpell = 8921, names = { ["zhCN"] = "平衡", ["zhTW"] = "平衡", ["enUS"] = "Balance", ["koKR"] = "조화", ["deDE"] = "Gleichgewicht", ["esES"] = "Equilibrio", ["esMX"] = "Equilibrio", ["itIT"] = "Equilibrio", ["ptBR"] = "Equilíbrio", ["frFR"] = "Équilibre", ["ruRU"] = "Баланс" } }, --月火
    { id = 103, name = "野性", classID = 11, icon = 132115, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 22568, names = { ["zhCN"] = "野性", ["zhTW"] = "野性戰鬥", ["enUS"] = "Feral", ["koKR"] = "야성", ["deDE"] = "Wildheit", ["esES"] = "Feral", ["esMX"] = "Feral", ["itIT"] = "Aggressore Ferino", ["ptBR"] = "Feral", ["frFR"] = "Farouche", ["ruRU"] = "Сила зверя" } }, --咬
    { id = 104, name = "守护", classID = 11, icon = 132276, role = "TANK", primaryStat = "敏捷", RangeSpell = 33917, names = { ["zhCN"] = "守护", ["zhTW"] = "守護者", ["enUS"] = "Guardian", ["koKR"] = "수호", ["deDE"] = "Wächter", ["esES"] = "Guardián", ["esMX"] = "Guardián", ["itIT"] = "Guardiano Ferino", ["ptBR"] = "Guardião", ["frFR"] = "Gardien", ["ruRU"] = "Страж" } }, --列
    { id = 105, name = "恢复", classID = 11, icon = 136041, role = "HEALER", primaryStat = "智力", RangeSpell = 8921, names = { ["zhCN"] = "恢复", ["zhTW"] = "恢復", ["enUS"] = "Restoration", ["koKR"] = "회복", ["deDE"] = "Wiederherstellung", ["esES"] = "Restauración", ["esMX"] = "Restauración", ["itIT"] = "Rigenerazione", ["ptBR"] = "Restauração", ["frFR"] = "Restauration", ["ruRU"] = "Исцеление" } }, --月火

    -- 死亡骑士 (6) - 力量
    { id = 250, name = "鲜血", classID = 6, icon = 135770, role = "TANK", primaryStat = "力量", RangeSpell = 49998, names = { ["zhCN"] = "鲜血", ["zhTW"] = "血魄", ["enUS"] = "Blood", ["koKR"] = "혈기", ["deDE"] = "Blut", ["esES"] = "Sangre", ["esMX"] = "Sangre", ["itIT"] = "Sangue", ["ptBR"] = "Sangue", ["frFR"] = "Sang", ["ruRU"] = "Кровь" } }, --灵打
    { id = 251, name = "冰霜", classID = 6, icon = 135773, role = "DAMAGER", primaryStat = "力量", RangeSpell = 49998, names = { ["zhCN"] = "冰霜", ["zhTW"] = "冰霜", ["enUS"] = "Frost", ["koKR"] = "냉기", ["deDE"] = "Frost", ["esES"] = "Escarcha", ["esMX"] = "Escarcha", ["itIT"] = "Gelo", ["ptBR"] = "Gélido", ["frFR"] = "Givre", ["ruRU"] = "Лед" } }, --灵打
    { id = 252, name = "邪恶", classID = 6, icon = 135775, role = "DAMAGER", primaryStat = "力量", RangeSpell = 49998, names = { ["zhCN"] = "邪恶", ["zhTW"] = "穢邪", ["enUS"] = "Unholy", ["koKR"] = "부정", ["deDE"] = "Unheilig", ["esES"] = "Profano", ["esMX"] = "Profano", ["itIT"] = "Empietà", ["ptBR"] = "Profano", ["frFR"] = "Impie", ["ruRU"] = "Нечестивость" } }, --灵打

    -- 猎人 (3) - 敏捷
    { id = 253, name = "野兽控制", classID = 3, icon = 461112, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 187707, names = { ["zhCN"] = "野兽控制", ["zhTW"] = "野獸控制", ["enUS"] = "Beast Mastery", ["koKR"] = "야수", ["deDE"] = "Tierherrschaft", ["esES"] = "Bestias", ["esMX"] = "Bestias", ["itIT"] = "Affinità Animale", ["ptBR"] = "Domínio das Feras", ["frFR"] = "Maîtrise des bêtes", ["ruRU"] = "Повелитель зверей" } }, --压制
    { id = 254, name = "射击", classID = 3, icon = 236179, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 147362, names = { ["zhCN"] = "射击", ["zhTW"] = "射擊", ["enUS"] = "Marksmanship", ["koKR"] = "사격", ["deDE"] = "Treffsicherheit", ["esES"] = "Puntería", ["esMX"] = "Puntería", ["itIT"] = "Precisione di Tiro", ["ptBR"] = "Precisão", ["frFR"] = "Précision", ["ruRU"] = "Стрельба" } }, --反制射击
    { id = 255, name = "生存", classID = 3, icon = 461113, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 147362, names = { ["zhCN"] = "生存", ["zhTW"] = "生存", ["enUS"] = "Survival", ["koKR"] = "생존", ["deDE"] = "Überleben", ["esES"] = "Supervivencia", ["esMX"] = "Supervivencia", ["itIT"] = "Sopravvivenza", ["ptBR"] = "Sobrevivência", ["frFR"] = "Survie", ["ruRU"] = "Выживание" } }, --反制射击

    -- 牧师 (5) - 智力
    { id = 256, name = "戒律", classID = 5, icon = 135940, role = "HEALER", primaryStat = "智力", RangeSpell = 585, names = { ["zhCN"] = "戒律", ["zhTW"] = "戒律", ["enUS"] = "Discipline", ["koKR"] = "수양", ["deDE"] = "Disziplin", ["esES"] = "Disciplina", ["esMX"] = "Disciplina", ["itIT"] = "Disciplina", ["ptBR"] = "Disciplina", ["frFR"] = "Discipline", ["ruRU"] = "Послушание" } }, --惩击
    { id = 257, name = "神圣", classID = 5, icon = 237542, role = "HEALER", primaryStat = "智力", RangeSpell = 585, names = { ["zhCN"] = "神圣", ["zhTW"] = "神聖", ["enUS"] = "Holy", ["koKR"] = "신성", ["deDE"] = "Heilig", ["esES"] = "Sagrado", ["esMX"] = "Sagrado", ["itIT"] = "Sacro", ["ptBR"] = "Sagrado", ["frFR"] = "Sacré", ["ruRU"] = "Свет" } }, --惩击
    { id = 258, name = "暗影", classID = 5, icon = 136207, role = "DAMAGER", primaryStat = "智力", RangeSpell = 8902, names = { ["zhCN"] = "暗影", ["zhTW"] = "暗影", ["enUS"] = "Shadow", ["koKR"] = "암흑", ["deDE"] = "Schatten", ["esES"] = "Sombra", ["esMX"] = "Sombra", ["itIT"] = "Ombra", ["ptBR"] = "Sombra", ["frFR"] = "Ombre", ["ruRU"] = "Тьма" } }, --震爆

    -- 潜行者 (4) - 敏捷
    { id = 259, name = "奇袭", classID = 4, icon = 236270, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 1766, names = { ["zhCN"] = "奇袭", ["zhTW"] = "刺殺", ["enUS"] = "Assassination", ["koKR"] = "암살", ["deDE"] = "Meucheln", ["esES"] = "Asesinato", ["esMX"] = "Asesinato", ["itIT"] = "Assassinio", ["ptBR"] = "Assassinato", ["frFR"] = "Assassinat", ["ruRU"] = "Ликвидация" } }, --脚踢
    { id = 260, name = "狂徒", classID = 4, icon = 236286, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 1766, names = { ["zhCN"] = "狂徒", ["zhTW"] = "暴徒", ["enUS"] = "Outlaw", ["koKR"] = "무법", ["deDE"] = "Gesetzlosigkeit", ["esES"] = "Forajido", ["esMX"] = "Forajido", ["itIT"] = "Fuorilegge", ["ptBR"] = "Fora da Lei", ["frFR"] = "Hors-la-loi", ["ruRU"] = "Головорез" } }, --脚踢
    { id = 261, name = "敏锐", classID = 4, icon = 132320, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 1766, names = { ["zhCN"] = "敏锐", ["zhTW"] = "敏銳", ["enUS"] = "Subtlety", ["koKR"] = "잠행", ["deDE"] = "Täuschung", ["esES"] = "Sutileza", ["esMX"] = "Sutileza", ["itIT"] = "Scaltrezza", ["ptBR"] = "Subterfúgio", ["frFR"] = "Finesse", ["ruRU"] = "Скрытность" } }, --脚踢

    -- 萨满祭司 (7) - 敏捷/智力
    { id = 262, name = "元素", classID = 7, icon = 136048, role = "DAMAGER", primaryStat = "智力", RangeSpell = 188196, names = { ["zhCN"] = "元素", ["zhTW"] = "元素", ["enUS"] = "Elemental", ["koKR"] = "정기", ["deDE"] = "Elementar", ["esES"] = "Elemental", ["esMX"] = "Elemental", ["itIT"] = "Elementale", ["ptBR"] = "Elemental", ["frFR"] = "Élémentaire", ["ruRU"] = "Стихии" } }, -- 闪电箭
    { id = 263, name = "增强", classID = 7, icon = 237581, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 60103, names = { ["zhCN"] = "增强", ["zhTW"] = "增強", ["enUS"] = "Enhancement", ["koKR"] = "고양", ["deDE"] = "Verstärkung", ["esES"] = "Mejora", ["esMX"] = "Mejora", ["itIT"] = "Potenziamento", ["ptBR"] = "Aperfeiçoamento", ["frFR"] = "Amélioration", ["ruRU"] = "Совершенствование" } }, --熔岩猛击
    { id = 264, name = "恢复", classID = 7, icon = 136052, role = "HEALER", primaryStat = "智力", RangeSpell = 188196, names = { ["zhCN"] = "恢复", ["zhTW"] = "恢復", ["enUS"] = "Restoration", ["koKR"] = "복원", ["deDE"] = "Wiederherstellung", ["esES"] = "Restauración", ["esMX"] = "Restauración", ["itIT"] = "Rigenerazione", ["ptBR"] = "Restauração", ["frFR"] = "Restauration", ["ruRU"] = "Исцеление" } }, -- 闪电箭

    -- 术士 (9) - 智力
    { id = 265, name = "痛苦", classID = 9, icon = 136145, role = "DAMAGER", primaryStat = "智力", RangeSpell = 686, names = { ["zhCN"] = "痛苦", ["zhTW"] = "痛苦", ["enUS"] = "Affliction", ["koKR"] = "고통", ["deDE"] = "Gebrechen", ["esES"] = "Aflicción", ["esMX"] = "Aflicción", ["itIT"] = "Afflizione", ["ptBR"] = "Suplício", ["frFR"] = "Affliction", ["ruRU"] = "Колдовство" } }, --暗影箭
    { id = 266, name = "恶魔学识", classID = 9, icon = 136172, role = "DAMAGER", primaryStat = "智力", RangeSpell = 105174, names = { ["zhCN"] = "恶魔学识", ["zhTW"] = "惡魔學識", ["enUS"] = "Demonology", ["koKR"] = "악마", ["deDE"] = "Dämonologie", ["esES"] = "Demonología", ["esMX"] = "Demonología", ["itIT"] = "Demonologia", ["ptBR"] = "Demonologia", ["frFR"] = "Démonologie", ["ruRU"] = "Демонология" } }, --古尔丹之手
    { id = 267, name = "毁灭", classID = 9, icon = 136186, role = "DAMAGER", primaryStat = "智力", RangeSpell = 116858, names = { ["zhCN"] = "毁灭", ["zhTW"] = "毀滅", ["enUS"] = "Destruction", ["koKR"] = "파괴", ["deDE"] = "Zerstörung", ["esES"] = "Destrucción", ["esMX"] = "Destrucción", ["itIT"] = "Distruzione", ["ptBR"] = "Destruição", ["frFR"] = "Destruction", ["ruRU"] = "Разрушение" } }, --混乱箭

    -- 武僧 (10) - 敏捷
    { id = 268, name = "酒仙", classID = 10, icon = 608951, role = "TANK", primaryStat = "敏捷", RangeSpell = 100780, names = { ["zhCN"] = "酒仙", ["zhTW"] = "釀酒", ["enUS"] = "Brewmaster", ["koKR"] = "양조", ["deDE"] = "Braumeister", ["esES"] = "Maestro cervecero", ["esMX"] = "Maestro cervecero", ["itIT"] = "Mastro Birraio", ["ptBR"] = "Mestre Cervejeiro", ["frFR"] = "Maître brasseur", ["ruRU"] = "Хмелевар" } }, --虎掌
    { id = 269, name = "踏风", classID = 10, icon = 608953, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 100780, names = { ["zhCN"] = "踏风", ["zhTW"] = "御風", ["enUS"] = "Windwalker", ["koKR"] = "풍운", ["deDE"] = "Windläufer", ["esES"] = "Viajero del viento", ["esMX"] = "Viajero del viento", ["itIT"] = "Impeto", ["ptBR"] = "Andarilho do Vento", ["frFR"] = "Marche-vent", ["ruRU"] = "Танцующий с ветром" } }, --虎掌
    { id = 270, name = "织雾", classID = 10, icon = 608952, role = "HEALER", primaryStat = "智力", RangeSpell = 100780, names = { ["zhCN"] = "织雾", ["zhTW"] = "織霧", ["enUS"] = "Mistweaver", ["koKR"] = "운무", ["deDE"] = "Nebelwirker", ["esES"] = "Tejedor de niebla", ["esMX"] = "Tejedor de niebla", ["itIT"] = "Misticismo", ["ptBR"] = "Tecelão da Névoa", ["frFR"] = "Tisse-brume", ["ruRU"] = "Ткач туманов" } }, --虎掌

    -- 恶魔猎手 (12) - 敏捷
    { id = 577, name = "浩劫", classID = 12, icon = 1247264, role = "DAMAGER", primaryStat = "敏捷", RangeSpell = 162794, names = { ["zhCN"] = "浩劫", ["zhTW"] = "災虐", ["enUS"] = "Havoc", ["koKR"] = "파멸", ["deDE"] = "Verwüstung", ["esES"] = "Devastación", ["esMX"] = "Caos", ["itIT"] = "Rovina", ["ptBR"] = "Devastação", ["frFR"] = "Dévastation", ["ruRU"] = "Истребление" } }, --混打
    { id = 581, name = "复仇", classID = 12, icon = 1247265, role = "TANK", primaryStat = "敏捷", RangeSpell = 263642, names = { ["zhCN"] = "复仇", ["zhTW"] = "復仇", ["enUS"] = "Vengeance", ["koKR"] = "복수", ["deDE"] = "Rachsucht", ["esES"] = "Venganza", ["esMX"] = "Venganza", ["itIT"] = "Vendetta", ["ptBR"] = "Vingança", ["frFR"] = "Vengeance", ["ruRU"] = "Месть" } }, --破裂
    { id = 1480, name = "噬灭", classID = 12, icon = 7455385, role = "DAMAGER", primaryStat = "智力", RangeSpell = 473662, names = { ["zhCN"] = "噬灭", ["zhTW"] = "噬滅", ["enUS"] = "Devourer", ["koKR"] = "포식", ["deDE"] = "Verschlinger", ["esES"] = "Devorador", ["esMX"] = "Devoración", ["itIT"] = "Divoratore", ["ptBR"] = "Devorador", ["frFR"] = "Dévoration", ["ruRU"] = "Пожиратель" } }, --吞噬

    -- 唤魔师 (13) - 智力
    { id = 1467, name = "湮灭", classID = 13, icon = 4511811, role = "DAMAGER", primaryStat = "智力", RangeSpell = 362969, names = { ["zhCN"] = "湮灭", ["zhTW"] = "破滅", ["enUS"] = "Devastation", ["koKR"] = "황폐", ["deDE"] = "Verheerung", ["esES"] = "Devastación", ["esMX"] = "Devastación", ["itIT"] = "Devastazione", ["ptBR"] = "Devastação", ["frFR"] = "Dévastation", ["ruRU"] = "Опустошитель" } }, --碧蓝打击
    { id = 1468, name = "恩护", classID = 13, icon = 4511812, role = "HEALER", primaryStat = "智力", RangeSpell = 362969, names = { ["zhCN"] = "恩护", ["zhTW"] = "護存", ["enUS"] = "Preservation", ["koKR"] = "보존", ["deDE"] = "Bewahrung", ["esES"] = "Preservación", ["esMX"] = "Preservación", ["itIT"] = "Conservazione", ["ptBR"] = "Preservação", ["frFR"] = "Préservation", ["ruRU"] = "Хранитель" } }, --碧蓝打击
    { id = 1473, name = "增辉", classID = 13, icon = 5198700, role = "DAMAGER", primaryStat = "智力", RangeSpell = 395160, names = { ["zhCN"] = "增辉", ["zhTW"] = "強化", ["enUS"] = "Augmentation", ["koKR"] = "증강", ["deDE"] = "Verstärkung", ["esES"] = "Aumento", ["esMX"] = "Aumento", ["itIT"] = "Fortificazione", ["ptBR"] = "Aprimoramento", ["frFR"] = "Augmentation", ["ruRU"] = "Насыщатель" } }, --喷发
}

-- DB2（ChrClasses / ChrSpecialization）本地化名称。顺序固定为 DB_LOCALIZATION_LOCALES。

-- 专精ID -> 专精数据
EXDB.SpecByID = {}
-- 专精ID -> 角色键（tank/heal/dps）
EXDB.SpecRoleKeyByID = {}
-- 按角色分组的专精列表
EXDB.SpecsByRole = {
    tank = {},
    heal = {},
    dps = {},
}
-- 职业ID -> 专精列表
EXDB.SpecsByClassID = {}
for _, spec in ipairs(EXDB.Specs) do
    EXDB.SpecByID[spec.id] = spec

    local roleKey
    if spec.role == "TANK" then
        roleKey = "tank"
    elseif spec.role == "HEALER" then
        roleKey = "heal"
    elseif spec.role == "DAMAGER" or spec.role == "DPS" then
        roleKey = "dps"
    end
    EXDB.SpecRoleKeyByID[spec.id] = roleKey

    if roleKey and EXDB.SpecsByRole[roleKey] then
        table.insert(EXDB.SpecsByRole[roleKey], spec)
    end

    if spec.classID then
        EXDB.SpecsByClassID[spec.classID] = EXDB.SpecsByClassID[spec.classID] or {}
        table.insert(EXDB.SpecsByClassID[spec.classID], spec)
    end
end

-- 坦克专精列表
EXDB.TankSpecs = {
    [66] = true,  -- 圣骑士-防护
    [73] = true,  -- 战士-防护
    [104] = true, -- 德鲁伊-守护
    [250] = true, -- 死亡骑士-鲜血
    [268] = true, -- 武僧-酒仙
    [581] = true, -- 恶魔猎手-复仇
}

-- 治疗专精列表
EXDB.HealerSpecs = {
    [65] = true,   -- 圣骑士-神圣
    [105] = true,  -- 德鲁伊-恢复
    [256] = true,  -- 牧师-戒律
    [257] = true,  -- 牧师-神圣
    [264] = true,  -- 萨满祭司-恢复
    [270] = true,  -- 武僧-织雾
    [1468] = true, -- 唤魔师-恩护
}

-- 职业排序 (常用排序: DK, 战士, 骑士, 猎人, 萨满, 唤魔师, 盗贼, DH, 武僧, 德鲁伊, 法师, 术士, 牧师)
EXDB.ClassOrder = { 6, 1, 2, 3, 7, 13, 4, 12, 10, 11, 8, 9, 5 }

-------------------------------------------------------
-- 全职业打断技能数据 (用于 ExM+.InterruptTracker 等)
-- [SpecID] = { id = SpellID, cd = BaseSeconds }
-- 仅包含核心打断技能(Kick/Counterspell等)。无打断专精 id=0。
-------------------------------------------------------
EXDB.InterruptData = {
    -- 死亡骑士 (Death Knight)
    [250] = { id = 47528, cd = 12 }, -- 鲜血: 心灵冰冻
    [251] = { id = 47528, cd = 12 }, -- 冰霜: 心灵冰冻
    [252] = { id = 47528, cd = 12 }, -- 邪恶: 心灵冰冻

    -- 恶魔猎手 (Demon Hunter)
    [577] = { id = 183752, cd = 15 }, -- 浩劫: 吞噬魔法
    [581] = { id = 183752, cd = 15 }, -- 复仇: 吞噬魔法
    [1480] = { id = 183752, cd = 15 },
    -- 德鲁伊 (Druid)
    [102] = { id = 0, cd = 0 },       -- 平衡: 日光术(不启用)
    [103] = { id = 106839, cd = 15 }, -- 野性: 迎头痛击
    [104] = { id = 106839, cd = 15 }, -- 守护: 迎头痛击
    [105] = { id = 0, cd = 0 },       -- 恢复: 无

    -- 唤魔师 (Evoker)
    [1467] = { id = 351338, cd = 20 }, -- 湮灭: 镇压
    [1468] = { id = 0, cd = 0 },       -- 恩护: 无
    [1473] = { id = 351338, cd = 18 }, -- 增辉: 镇压

    -- 猎人 (Hunter)
    [253] = { id = 147362, cd = 24 }, -- 兽王: 反制射击
    [254] = { id = 147362, cd = 24 }, -- 射击: 反制射击
    [255] = { id = 187707, cd = 15 }, -- 生存: 压制

    -- 法师 (Mage)
    [62] = { id = 2139, cd = 20 }, -- 奥术: 法术反制
    [63] = { id = 2139, cd = 20 }, -- 火焰: 法术反制
    [64] = { id = 2139, cd = 20 }, -- 冰霜: 法术反制

    -- 武僧 (Monk)
    [268] = { id = 116705, cd = 15 }, -- 酒仙: 切喉手
    [269] = { id = 116705, cd = 15 }, -- 踏风: 切喉手
    [270] = { id = 0, cd = 0 },       -- 织雾: 无

    -- 圣骑士 (Paladin)
    [66] = { id = 96231, cd = 15 }, -- 防护: 责难
    [70] = { id = 96231, cd = 15 }, -- 惩戒: 责难
    [65] = { id = 0, cd = 0 },      -- 神圣: 无

    -- 牧师 (Priest)
    [258] = { id = 15487, cd = 30 }, -- 暗影: 沉默
    [256] = { id = 0, cd = 0 },      -- 戒律: 无
    [257] = { id = 0, cd = 0 },      -- 神圣: 无

    -- 潜行者 (Rogue)
    [259] = { id = 1766, cd = 15 }, -- 奇袭: 脚踢
    [260] = { id = 1766, cd = 15 }, -- 狂徒: 脚踢
    [261] = { id = 1766, cd = 15 }, -- 敏锐: 脚踢

    -- 萨满祭司 (Shaman)
    [262] = { id = 57994, cd = 12 }, -- 元素: 风剪
    [263] = { id = 57994, cd = 12 }, -- 增强: 风剪
    [264] = { id = 57994, cd = 30 }, -- 恢复: 风剪

    -- 术士 (Warlock)
    [265] = { id = 19647, cd = 24 }, -- 痛苦: 法术封锁
    [266] = { id = 89766, cd = 30 }, -- 恶魔: 法术封锁
    [267] = { id = 19647, cd = 24 }, -- 毁灭: 法术封锁

    -- 战士 (Warrior)
    [71] = { id = 6552, cd = 15 }, -- 武器: 拳击
    [72] = { id = 6552, cd = 15 }, -- 狂怒: 拳击
    [73] = { id = 6552, cd = 15 }, -- 防护: 拳击
}

-------------------------------------------------------
-- 传送门数据 (大秘境/副本)
-------------------------------------------------------
EXDB.TeleportData = {
    -- 3.0
    ["萨隆矿坑"] = 1254555,
    -- 4.0
    ["格瑞姆巴托"] = 445424,
    ["旋云之巅"] = 410080,
    ["潮汐王座"] = 424142,
    -- 5.0
    ["通灵学院"] = 131232,
    ["青龙寺"] = 131204,
    ["风暴烈酒酿造厂"] = 131205,
    ["影踪禅院"] = 131206,
    ["魔古山宫殿"] = 131222,
    ["残阳关"] = 131225,
    ["围攻砮皂寺"] = 131228,
    ["血色修道院"] = 131229,
    ["血色大厅"] = 131231,
    -- 6.0
    ["奥金顿"] = 159897,
    ["通天峰"] = 1254557,
    ["影月墓地"] = 159899,
    ["永茂林地"] = 159901,
    ["黑石塔上层"] = 159902,
    ["血槌炉渣矿井"] = 159895,
    ["恐轨车站"] = 159900,
    ["钢铁码头"] = 159896,
    -- 7.0
    ["卡拉赞"] = 373262,
    ["群星庭院"] = 393766,
    ["英灵殿"] = 393764,
    ["黑鸦堡垒"] = 424153,
    ["黑心林地"] = 424163,
    ["奈萨里奥的巢穴"] = 410078,
    ["执政团之座"] = 1254551,
    -- 8.0
    ["麦卡贡行动"] = 373274,
    ["自由镇"] = 410071,
    ["地渊孢林"] = 410074,
    ["维克雷斯庄园"] = 424167,
    ["阿塔达萨"] = 424187,
    ["围攻伯拉勒斯"] = 445418,
    ["塞塔里斯神庙"] = 1286828,
    ["暴富矿区！！"] = 467553,
    ["诸王之眠"] = 1286831,
    -- 9.0
    ["通灵战潮"] = 354462,
    ["凋魂之殇"] = 354463,
    ["塞兹仙林的迷雾"] = 354464,
    ["赎罪大厅"] = 354465,
    ["晋升高塔"] = 354466,
    ["伤逝剧场"] = 354467,
    ["彼界"] = 354468,
    ["赤红深渊"] = 354469,
    ["塔扎维什"] = 367416,
    ["纳斯利亚堡"] = 373190,
    ["统御圣所"] = 373191,
    ["初诞者圣墓"] = 373192,
    -- 10.0
    ["奥达曼"] = 393222,
    ["红玉新生法池"] = 393256,
    ["诺库德阻击战"] = 393262,
    ["蕨皮山谷"] = 393267,
    ["艾杰斯亚学院"] = 393273,
    ["奈萨鲁斯"] = 393276,
    ["碧蓝魔馆"] = 393279,
    ["注能大厅"] = 393283,
    ["永恒黎明"] = 424197,
    ["化身巨龙牢窟"] = 432254,
    ["亚贝鲁斯"] = 432257,
    ["阿梅达希尔"] = 432258,
    -- 11.0
    ["驭雷栖巢"] = 445443,
    ["矶石宝库"] = 445269,
    ["圣焰隐修院"] = 445444,
    ["千丝之城"] = 445416,
    ["燧酿酒庄"] = 445440,
    ["暗焰裂口"] = 445441,
    ["破晨号"] = 445414,
    ["艾拉-卡拉"] = 445417,
    ["水闸行动"] = 1216786,
    ["解放安德麦"] = 1226482,
    ["奥尔达尼生态圆顶"] = 1237215,
    ["法力熔炉:欧米伽"] = 1239155,
    -- 12.0
    ["风行者之塔"] = 1254400,
    ["魔导师平台"] = 1254572,
    ["迈萨拉洞窟"] = 1254559,
    ["节点希纳斯"] = 1254563,
    ["毒牙祭坛"] = 1286812,
    ["密谋小径"] = 1286809,
    ["纳洛拉克的洞穴"] = 1286807,
    ["虚空之痕竞技场"] = 1286804,
    ["夺目谷"] = 1286801
}

-------------------------------------------------------
-- 副本图标映射 (mapID -> iconFileID)
-- 规则: 同一 mapID 多次出现时，后出现覆盖前面。
-------------------------------------------------------
EXDB.InstanceIconSource = {
    { "烈毒之渊", 3004, 8039391 },
    { "毒牙祭坛", 2993, 7956176 },
    { "潮缚石窟", 2987, 8164250 },
    { "孢陨幽境", 1592, 7852000 },
    { "梦境裂隙", 2939, 7570496 },
    { "至暗之夜", 2930, 7644019 },
    { "虚空之痕竞技场", 2923, 7479112 },
    { "节点希纳斯", 2915, 7570495 },
    { "进军奎尔丹纳斯", 2913, 7480127 },
    { "虚影尖塔", 2912, 7507136 },
    { "迈萨拉洞窟", 2874, 7478535 },
    { "夺目谷", 2859, 7478534 },
    { "奥尔达尼生态圆顶", 2830, 7074037 },
    { "纳洛拉克的洞穴", 2825, 7478536 },
    { "密谋小径", 2813, 7467179 },
    { "魔导师平台", 2811, 7467178 },
    { "法力熔炉：欧米伽", 2810, 7049159 },
    { "风行者之塔", 2805, 7464936 },
    { "黑石深渊", 2792, 136326 },
    { "卡兹阿加", 2774, 5917061 },
    { "水闸行动", 2773, 6422372 },
    { "解放安德麦", 2769, 6422371 },
    { "千丝之城", 2669, 5912509 },
    { "破晨号", 2662, 5912513 },
    { "燧酿酒庄", 2661, 5912508 },
    { "艾拉-卡拉，回响之城", 2660, 5912507 },
    { "尼鲁巴尔王宫", 2657, 5912511 },
    { "矶石宝库", 2652, 5912515 },
    { "暗焰裂口", 2651, 5912510 },
    { "圣焰隐修院", 2649, 5912512 },
    { "驭雷栖巢", 2648, 5912514 },
    { "永恒黎明", 2579, 5221804 },
    { "巨龙群岛", 2574, 4746637 },
    { "亚贝鲁斯，焰影熔炉", 2569, 5149415 },
    { "暗影界", 2559, 3850571 },
    { "阿梅达希尔，梦境之愿", 2549, 5409263 },
    { "注能大厅", 2527, 4746638 },
    { "艾杰斯亚学院", 2526, 4746641 },
    { "化身巨龙牢窟", 2522, 4746643 },
    { "红玉新生法池", 2521, 4746639 },
    { "蕨皮山谷", 2520, 4746635 },
    { "奈萨鲁斯", 2519, 4746640 },
    { "诺库德阻击战", 2516, 4746636 },
    { "碧蓝魔馆", 2515, 4746634 },
    { "初诞者圣墓", 2481, 4423750 },
    { "奥达曼：提尔的遗产", 2451, 4746642 },
    { "统御圣所", 2450, 4181530 },
    { "塔扎维什，帷纱集市", 2441, 4181531 },
    { "纳斯利亚堡", 2296, 3759926 },
    { "伤逝剧场", 2293, 3759934 },
    { "彼界", 2291, 3759935 },
    { "塞兹仙林的迷雾", 2290, 3759929 },
    { "凋魂之殇", 2289, 3759931 },
    { "赎罪大厅", 2287, 3759928 },
    { "通灵战潮", 2286, 3759930 },
    { "晋升高塔", 2285, 3759933 },
    { "赤红深渊", 2284, 3759932 },
    { "尼奥罗萨，觉醒之城", 2217, 3221466 },
    { "永恒王宫", 2164, 3025335 },
    { "麦卡贡行动", 2097, 3025336 },
    { "风暴熔炉", 2096, 2498195 },
    { "达萨罗之战", 2070, 2482693 },
    { "塞塔里斯神庙", 1877, 2178734 },
    { "风暴神殿", 1864, 2178732 },
    { "维克雷斯庄园", 1862, 2178742 },
    { "奥迪尔", 1861, 2178738 },
    { "艾泽拉斯", 1861, 2178743 },
    { "地渊孢林", 1841, 2178736 },
    { "围攻伯拉勒斯", 1822, 2178733 },
    { "托尔达戈", 1771, 2178737 },
    { "阿塔达萨", 1763, 1778896 },
    { "诸王之眠", 1762, 2178730 },
    { "自由镇", 1754, 1778897 },
    { "执政团之座", 1753, 1718526 },
    { "安托鲁斯，燃烧王座", 1712, 1718524 },
    { "永夜大教堂", 1677, 1616925 },
    { "萨格拉斯之墓", 1676, 1616207 },
    { "重返卡拉赞", 1651, 1537287 },
    { "勇气试炼", 1648, 1537288 },
    { "暴富矿区！！", 1594, 2178735 },
    { "群星庭院", 1571, 1498160 },
    { "突袭紫罗兰监狱", 1544, 1498159 },
    { "暗夜要塞", 1530, 1450577 },
    { "破碎群岛", 1520, 1411866 },
    { "侵入点", 1520, 1718525 },
    { "翡翠梦魇", 1520, 1452699 },
    { "魔法回廊", 1516, 1411869 },
    { "黑鸦堡垒", 1501, 1411865 },
    { "守望者地窟", 1493, 1411870 },
    { "噬魂之喉", 1492, 1411868 },
    { "英灵殿", 1477, 1498162 },
    { "黑心林地", 1466, 1411867 },
    { "奈萨里奥的巢穴", 1458, 1450576 },
    { "艾萨拉之眼", 1456, 1498161 },
    { "地狱火堡垒", 1448, 136340 },
    { "黑石塔上层", 1358, 1042065 },
    { "永茂林地", 1279, 1060551 },
    { "德拉诺", 1228, 1042060 },
    { "悬槌堡", 1228, 1042062 },
    { "通天峰", 1209, 1042064 },
    { "恐轨车站", 1208, 1042061 },
    { "黑石铸造厂", 1205, 1042058 },
    { "钢铁码头", 1195, 1060552 },
    { "奥金顿", 1182, 1042057 },
    { "影月墓地", 1176, 1042063 },
    { "血槌炉渣矿井", 1175, 1042059 },
    { "萨隆矿坑", 658, 336391 },
}

EXDB.InstanceIconByMapID = {}
for _, row in ipairs(EXDB.InstanceIconSource) do
    local mapID = tonumber(row[2])
    local icon = tonumber(row[3])
    if mapID and icon then
        EXDB.InstanceIconByMapID[mapID] = icon
    end
end

-------------------------------------------------------
-- 副本 / 首领备注数据源
-- 说明:
-- 1. 以 mapID 为主键组织副本基础信息
-- 2. 同时提供 instanceID 索引，便于直接对接 State.InstanceID
-- 3. 首领数据按 encounterID 建立索引，并挂回所属副本
-------------------------------------------------------
-- BEGIN GENERATED S2 NPC LOCALES
EXDB.NPCNameSource = {
    [133384] = { enUS = "Merektha", koKR = "메레크타", frFR = "Merekpha", deDE = "Merektha", zhCN = "米利克萨", ptBR = "Merektha", esES = "Merektha", ruRU = "Меректа", esMX = "Merektha", itIT = "Merektha", zhTW = "莫芮克莎" },
    [133392] = { enUS = "Avatar of Sethraliss", koKR = "세스랄리스의 화신", frFR = "Avatar de Sephraliss", deDE = "Avatar von Sethraliss", zhCN = "塞塔里斯的化身", ptBR = "Avatar de Sethraliss", esES = "Avatar de Sethraliss", ruRU = "Аватара Сетралисс", esMX = "Avatar de Sethraliss", itIT = "Avatar di Sethraliss", zhTW = "瑟沙利斯化身" },
    [133935] = { enUS = "Animated Guardian", koKR = "살아 움직이는 수호자", frFR = "Gardien animé", deDE = "Belebter Wächter", zhCN = "活化守卫", ptBR = "Guardião Animado", esES = "Guardián animado", ruRU = "Оживший страж", esMX = "Guardián animado", itIT = "Guardiano Animato", zhTW = "活化的守護者" },
    [133943] = { enUS = "Minion of Zul", koKR = "줄의 수하", frFR = "Séide de Zul", deDE = "Diener von Zul", zhCN = "祖尔的爪牙", ptBR = "Lacaio de Zul", esES = "Esbirro de Zul", ruRU = "Прислужник Зула", esMX = "Esbirro de Zul", itIT = "Servitore di Zul", zhTW = "祖爾之僕" },
    [134157] = { enUS = "Umbral Warrior", koKR = "암영 전사", frFR = "Guerrier ombreux", deDE = "Umbralkrieger", zhCN = "黯影战士", ptBR = "Guerreiro Umbrático", esES = "Guerrero umbrío", ruRU = "Теневой воин", esMX = "Guerrero umbrío", itIT = "Guerriero Ombrale", zhTW = "晦影戰士" },
    [134158] = { enUS = "Shadow-Borne Champion", koKR = "어둠태생 용사", frFR = "Champion portelombre", deDE = "Schattengeborener Champion", zhCN = "影裔勇士", ptBR = "Campeão Umbréreo", esES = "Campeón Sombralóbrega", ruRU = "Тенеликий защитник", esMX = "Campeón natosombra", itIT = "Campione della Genia dell'Ombra", zhTW = "影裔勇士" },
    [134174] = { enUS = "Risen Hexer", koKR = "되살아난 사술사", frFR = "Maléficieur ressuscité", deDE = "Auferstandener Hexer", zhCN = "复活的妖术师", ptBR = "Bagateiro Reanimado", esES = "Aojador resucitado", ruRU = "Восставший проклинатель", esMX = "Aojador resucitado", itIT = "Malefico Risorto", zhTW = "復生妖術師" },
    [134251] = { enUS = "Seneschal M'bara", koKR = "사무장 음바라", frFR = "Sénéchal M'bara", deDE = "Seneschall M'bara", zhCN = "总管姆巴拉", ptBR = "Senescal M'bara", esES = "Senescal M'bara", ruRU = "Сенешаль М'бара", esMX = "Senescal M'bara", itIT = "Siniscalco M'bara", zhTW = "瑪巴拉總管" },
    [134331] = { enUS = "King Rahu'ai", koKR = "왕 라후아이", frFR = "Roi Rahu'ai", deDE = "König Rahu'ai", zhCN = "拉胡艾大王", ptBR = "Rei Rahu'ai", esES = "Rey Rahu'ai", ruRU = "Король Рау'ай", esMX = "Rey Rahu'ai", itIT = "Re Rahu'ai", zhTW = "拉胡艾國王" },
    [134364] = { enUS = "Faithless Subjugator", koKR = "부정한 정복자", frFR = "Subjugateur infidèle", deDE = "Treuloser Unterwerfer", zhCN = "无信征服者", ptBR = "Subjugador Ímpio", esES = "Subyugador infiel", ruRU = "Отступник-подчинитель", esMX = "Subyugador infiel", itIT = "Plagiatore Senzafede", zhTW = "無信征服者" },
    [134388] = { enUS = "A Knot of Snakes", koKR = "뱀들의 똬리", frFR = "Noeud de serpents", deDE = "Schlangenknäuel", zhCN = "缠绕的蛇群", ptBR = "Nó de Cobras", esES = "Nudo de serpientes", ruRU = "Клубок змей", esMX = "", itIT = "Groviglio di Serpenti", zhTW = "蛇群" },
    [134389] = { enUS = "Toxic Viper", koKR = "독성 살무사", frFR = "Vipère toxique", deDE = "Toxische Viper", zhCN = "剧毒蝰蛇", ptBR = "Víbora Tóxica", esES = "Víbora tóxica", ruRU = "Ядовитая гадюка", esMX = "", itIT = "Vipera Tossica", zhTW = "劇毒爬蛇" },
    [134390] = { enUS = "Storm Serpent", koKR = "폭풍뱀", frFR = "Serpent des tempêtes", deDE = "Sturmschlange", zhCN = "风暴飞蛇", ptBR = "Serpente da Tempestade", esES = "Sierpe de tormenta", ruRU = "Штормовой змей", esMX = "", itIT = "Serpente della Tempesta", zhTW = "風暴毒蛇" },
    [134487] = { enUS = "Merektha", koKR = "메레크타", frFR = "Merekpha", deDE = "Merektha", zhCN = "米利克萨", ptBR = "Merektha", esES = "Merektha", ruRU = "Меректа", esMX = "", itIT = "Merektha", zhTW = "莫芮克莎" },
    [134599] = { enUS = "Imbued Stormcaller", koKR = "마력 깃든 폭풍소환사", frFR = "Mande-foudre imprégné", deDE = "Mächtiger Sturmrufer", zhCN = "灌注能量的唤雷者", ptBR = "Tempestário Imbuído", esES = "Clamatormentas imbuido", ruRU = "Усиленный призыватель шторма", esMX = "Clamatormentas imbuido", itIT = "Invocatore delle Tempeste Infuso", zhTW = "賦魔風暴召喚者" },
    [134600] = { enUS = "Sandswept Hunter", koKR = "모래받이 사냥꾼", frFR = "Chasseur ensablé", deDE = "Sandgepeitschter Jäger", zhCN = "流沙猎手", ptBR = "Caçador Areeiro", esES = "Cazador arrastrado por la arena", ruRU = "Песчаный охотник", esMX = "Cazador barrearena", itIT = "Cacciatore Sferzasabbia", zhTW = "荒漠獵人" },
    [134602] = { enUS = "Shrouded Fang", koKR = "가려진 송곳니", frFR = "Serpent camouflé", deDE = "Verhüllte Schlange", zhCN = "隐秘之牙", ptBR = "Presa Oculta", esES = "Colmillo velado", ruRU = "Скрытный убийца", esMX = "Colmillo camuflado", itIT = "Zanna Ammantata", zhTW = "利牙刺客" },
    [134616] = { enUS = "Barbed Krolusk", koKR = "미늘 크롤러스크", frFR = "Krolusk épineux", deDE = "Stachelkrolusk", zhCN = "倒刺三叶虫", ptBR = "Crolusco Farpado", esES = "Crolusco con púas", ruRU = "Колючий кролуск", esMX = "Krolusko espinoso", itIT = "Krolusk Uncinato", zhTW = "棘刺葉殼蟲" },
    [134629] = { enUS = "Sand-Sworn Rider", koKR = "모래서약 기수", frFR = "Coursier ligesable", deDE = "Sandgeschworener Reiter", zhCN = "砂誓骑兵", ptBR = "Cavalgante Jurareia", esES = "Jinete juraarenas", ruRU = "Присягнувший песку всадник", esMX = "Jinete jurarena", itIT = "Cavalcatore Giurasabbia", zhTW = "沙誓騎士" },
    [134686] = { enUS = "Krolusk Matriarch", koKR = "크롤러스크 어미", frFR = "Matriarche krolusk", deDE = "Kroluskmatriarchin", zhCN = "三叶虫主母", ptBR = "Matriarca Crolusco", esES = "Matriarca crolusco", ruRU = "Кролуск-матриарх", esMX = "Matriarca de kroluskos", itIT = "Matriarca Krolusk", zhTW = "葉殼蟲族母" },
    [134691] = { enUS = "Static Anomaly", koKR = "정전기 변형물", frFR = "Anomalie statique", deDE = "Statische Anomalie", zhCN = "静电异常体", ptBR = "Anomalia Estática", esES = "Anomalía estática", ruRU = "Статическая аномалия", esMX = "Anomalía estática", itIT = "Anomalia Statica", zhTW = "靜電異常體" },
    [134739] = { enUS = "Purification Construct", koKR = "정화 피조물", frFR = "Assemblage purificateur", deDE = "Läuterungskonstrukt", zhCN = "净化构造体", ptBR = "Constructo de Purificação", esES = "Ensamblaje de purificación", ruRU = "Голем-чистильщик", esMX = "Ensamblaje de purificación", itIT = "Costrutto della Purificazione", zhTW = "淨化的魔像" },
    [134990] = { enUS = "Storm Adept", koKR = "폭풍 숙련병", frFR = "Adepte des tempêtes", deDE = "Sturmadeptin", zhCN = "风暴能手", ptBR = "Adepta da Tempestade", esES = "Adepta de tormenta", ruRU = "Адепт бури", esMX = "Adepta de la tormenta", itIT = "Adepta della Tempesta", zhTW = "風暴精兵" },
    [134991] = { enUS = "Sandfury Stonefist", koKR = "성난모래 돌주먹", frFR = "Empoigneur furie-des-sables", deDE = "Steinfaust der Sandwüter", zhCN = "沙怒石拳战士", ptBR = "Punhopétreo Zangareia", esES = "Puñopiedra Furiarena", ruRU = "Крушитель из племени Песчаной Бури", esMX = "Puñopiedra furiarena", itIT = "Pugnosaldo Sabbiafurente", zhTW = "沙怒石拳" },
    [134993] = { enUS = "Mchimba the Embalmer", koKR = "장의사 음침바", frFR = "Mchimba l'Embaumeur", deDE = "Mchimba der Balsamierer", zhCN = "殓尸者姆沁巴", ptBR = "Muquimba, o Embalsamador", esES = "Mchimba el Embalsamador", ruRU = "Мчимба Бальзамировщик", esMX = "Mchimba el Embalsamador", itIT = "Mchimba l'Imbalsamatore", zhTW = "『墓葬者』瑪欽巴" },
    [135007] = { enUS = "Orb Watcher", koKR = "보주 감시자", frFR = "Surveillant d'orbe", deDE = "Kugelwächter", zhCN = "宝珠守望者", ptBR = "Vigia do Orbe", esES = "Vigilante de orbes", ruRU = "Смотритель сфер", esMX = "", itIT = "Guardiano del Globo", zhTW = "寶珠看守者" },
    [135167] = { enUS = "Royal Berserker", koKR = "왕실 광전사", frFR = "Berserker royal", deDE = "Königlicher Berserker", zhCN = "皇家狂战士", ptBR = "Berserker Real", esES = "Rabioso real", ruRU = "Королевский берсерк", esMX = "Rabioso real", itIT = "Berserker Reale", zhTW = "皇家狂戰士" },
    [135192] = { enUS = "Honored Raptor", koKR = "명예로운 랩터", frFR = "Raptor honoré", deDE = "Geehrter Raptor", zhCN = "荣耀迅猛龙", ptBR = "Raptor Honrado", esES = "Raptor honrado", ruRU = "Почитаемый ящер", esMX = "Raptor honrado", itIT = "Raptor Onorato", zhTW = "榮耀的迅猛龍" },
    [135204] = { enUS = "Phantom Hex Priest", koKR = "악령 사술 사제", frFR = "Prêtre maléficieur fantôme", deDE = "Phantomhexpriester", zhCN = "幻影妖术祭司", ptBR = "Sacerdote Bagateiro Fantasma", esES = "Sacerdote de maleficios fantasmal", ruRU = "Фантомный жрец-проклинатель", esMX = "Sacerdote de maleficios espectral", itIT = "Sacerdote del Maleficio Fantasma", zhTW = "魅影妖術祭司" },
    [135231] = { enUS = "Ghostly Brute", koKR = "유령 투사", frFR = "Brute fantomatique", deDE = "Geisterhafter Schläger", zhCN = "鬼魂蛮兵", ptBR = "Brutamontes Fantasma", esES = "Bruto fantasmal", ruRU = "Призрачный громила", esMX = "Bruto fantasmal", itIT = "Bruto Spettrale", zhTW = "鬼魅蠻卒" },
    [135239] = { enUS = "Spectral Shaman", koKR = "유령 주술사", frFR = "Chamane spectrale", deDE = "Spektrale Schamanin", zhCN = "幻影萨满祭司", ptBR = "Xamã Espectral", esES = "Chamán espectral", ruRU = "Призрачная шаманка", esMX = "Chamán espectral", itIT = "Sciamana Spettrale", zhTW = "鬼靈薩滿" },
    [135322] = { enUS = "The Golden Serpent", koKR = "황금 날뱀", frFR = "Le serpent doré", deDE = "Die Goldschlange", zhCN = "黄金风蛇", ptBR = "A Serpente Dourada", esES = "Serpiente dorada", ruRU = "Золотой Змей", esMX = "La serpiente dorada", itIT = "Serpente Dorato", zhTW = "黃金風蛇" },
    [135406] = { enUS = "Animated Gold", koKR = "살아 움직이는 황금", frFR = "Or animé", deDE = "Animiertes Gold", zhCN = "活性黄金", ptBR = "Ouro Animado", esES = "Oro animado", ruRU = "Ожившее золото", esMX = "", itIT = "Oro Animato", zhTW = "活化黃金" },
    [135445] = { enUS = "Lightning Spire", koKR = "번개의 첨탑", frFR = "Flèche de foudre", deDE = "Blitzspitze", zhCN = "闪电尖塔", ptBR = "Pináculo Elétrico", esES = "Aguja de relámpagos", ruRU = "Шпиль молний", esMX = "", itIT = "Spira Fulminante", zhTW = "閃電尖塔" },
    [135562] = { enUS = "Poisonous Viper", koKR = "독성 살무사", frFR = "Vipère venimeuse", deDE = "Giftviper", zhCN = "剧毒蝰蛇", ptBR = "Víbora Venenosa", esES = "Víbora ponzoñosa", ruRU = "Ядовитая гадюка", esMX = "Víbora venenosa", itIT = "Vipera Velenosa", zhTW = "劇毒毒蛇" },
    [135761] = { enUS = "Thundering Totem", koKR = "천둥치는 토템", frFR = "Totem fulgurant", deDE = "Totem des Donners", zhCN = "雷鸣图腾", ptBR = "Totem Trovejante", esES = "Tótem atronador", ruRU = "Громовой тотем", esMX = "", itIT = "Totem Tonante", zhTW = "雷擊圖騰" },
    [135764] = { enUS = "Explosive Totem", koKR = "폭발의 토템", frFR = "Totem explosif", deDE = "Totem der Explosion", zhCN = "爆裂图腾", ptBR = "Totem Explosivo", esES = "Tótem explosivo", ruRU = "Взрывной тотем", esMX = "", itIT = "Totem Esplosivo", zhTW = "爆裂圖騰" },
    [135765] = { enUS = "Torrent Totem", koKR = "격류의 토템", frFR = "Totem de torrent", deDE = "Totem des Stroms", zhCN = "洪流图腾", ptBR = "Totem da Torrente", esES = "Tótem de torrente", ruRU = "Тотем потоков", esMX = "", itIT = "Totem del Torrente", zhTW = "洪流圖騰" },
    [135846] = { enUS = "Lightning Serpent", koKR = "번개 뱀", frFR = "Serpent de foudre", deDE = "Blitzschlange", zhCN = "闪电毒蛇", ptBR = "Serpente Elétrica", esES = "Sierpe de relámpagos", ruRU = "Грозовой змей", esMX = "Serpiente de relámpagos", itIT = "Serpente Fulminante", zhTW = "雷霆巨蛇" },
    [135971] = { enUS = "Faithless Conscript", koKR = "부정한 징집병", frFR = "Conscrit infidèle", deDE = "Treuloser Rekrut", zhCN = "无信援兵", ptBR = "Convocado Ímpio", esES = "Recluta infiel", ruRU = "Отступник-новобранец", esMX = "", itIT = "Coscritto Senzafede", zhTW = "無信徵召兵" },
    [136076] = { enUS = "Agitated Nimbus", koKR = "흥분한 빛구름", frFR = "Nimbus agité", deDE = "Aufgebrachter Nimbus", zhCN = "暴怒云气", ptBR = "Nímbus Agitado", esES = "Nimbo inquieto", ruRU = "Беспокойное облако", esMX = "Nimbo agitado", itIT = "Nembo Agitato", zhTW = "躁亂雨雲" },
    [136160] = { enUS = "King Dazar", koKR = "왕 다자르", frFR = "Roi Dazar", deDE = "König Dazar", zhCN = "达萨大王", ptBR = "Rei Dazar", esES = "Rey Dazar", ruRU = "Король Дазар", esMX = "Rey Dazar", itIT = "Re Dazar", zhTW = "神王達薩" },
    [136250] = { enUS = "Twisted Hexxer", koKR = "뒤틀린 사술사", frFR = "Maléficieur dénaturé", deDE = "Entstellter Hexer", zhCN = "扭曲的妖术师", ptBR = "Bagateiro Perverso", esES = "Aojador retorcido", ruRU = "Искаженный проклинатель", esMX = "Aojador retorcido", itIT = "Malefico Corrotto", zhTW = "扭曲妖術師" },
    [136256] = { enUS = "Coffin", koKR = "관", frFR = "Cercueil", deDE = "Sarg", zhCN = "棺材", ptBR = "Caixão", esES = "Sarcófago", ruRU = "Саркофаг", esMX = "", itIT = "Bara", zhTW = "棺柩" },
    [136976] = { enUS = "T'zala", koKR = "트잘라", frFR = "T'zala", deDE = "T'zala", zhCN = "提扎拉", ptBR = "T'zala", esES = "T'zala", ruRU = "Т'зала", esMX = "", itIT = "T'zala", zhTW = "特札拉" },
    [136984] = { enUS = "Reban", koKR = "레반", frFR = "Reban", deDE = "Reban", zhCN = "莱班", ptBR = "Reban", esES = "Reban", ruRU = "Ребан", esMX = "", itIT = "Reban", zhTW = "瑞邦" },
    [137473] = { enUS = "Guard Captain Atu", koKR = "경비대장 아투", frFR = "Capitaine de la garde Atu", deDE = "Wachoffizier Atu", zhCN = "守卫队长阿图", ptBR = "Capitão da Guarda Atu", esES = "Capitán de la guardia Atu", ruRU = "Капитан стражи Ату", esMX = "Capitán de la guardia Atu", itIT = "Capitano della Guardia Atu", zhTW = "守衛隊長阿圖" },
    [137474] = { enUS = "King Timalji", koKR = "왕 티말지", frFR = "Roi Timalji", deDE = "König Timalji", zhCN = "提玛吉大王", ptBR = "Rei Timalji", esES = "Rey Timalji", ruRU = "Король Тималджи", esMX = "Rey Timalji", itIT = "Re Timalji", zhTW = "提瑪吉國王" },
    [137478] = { enUS = "Queen Wasi", koKR = "여왕 와시", frFR = "Reine Wasi", deDE = "Königin Wasi", zhCN = "沃希女王", ptBR = "Rainha Wasi", esES = "Reina Wasi", ruRU = "Королева Уаси", esMX = "Reina Wasi", itIT = "Regina Wasi", zhTW = "瓦希皇后" },
    [137484] = { enUS = "King A'akul", koKR = "왕 아아쿨", frFR = "Roi A'akul", deDE = "König A'akul", zhCN = "阿库尔大王", ptBR = "Rei A'akul", esES = "Rey A'akul", ruRU = "Король А'акул", esMX = "Rey A'akul", itIT = "Re A'akul", zhTW = "阿庫爾國王" },
    [137485] = { enUS = "Bloodsworn Assassin", koKR = "피의 서약 암살자", frFR = "Assassin ligessang", deDE = "Blutverschworener Assassine", zhCN = "血誓刺客", ptBR = "Assassino Jurassangue", esES = "Asesino Jurasangre", ruRU = "Одержимый кровью убийца", esMX = "Asesino jurasangre", itIT = "Assassino Giurasangue", zhTW = "血誓刺客" },
    [137486] = { enUS = "Queen Patlaa", koKR = "여왕 파틀라아", frFR = "Reine Patlaa", deDE = "Königin Patlaa", zhCN = "帕特拉女王", ptBR = "Rainha Patlaa", esES = "Reina Patlaa", ruRU = "Королева Патлаа", esMX = "Reina Patlaa", itIT = "Regina Patlaa", zhTW = "帕特拉皇后" },
    [137487] = { enUS = "Skeletal Hunting Raptor", koKR = "해골 사냥 랩터", frFR = "Raptor de chasse squelette", deDE = "Skelettjagdraptor", zhCN = "骸骨狩猎迅猛龙", ptBR = "Raptor Caçador Descarnado", esES = "Raptor de caza esquelético", ruRU = "Охотничий ящер", esMX = "Raptor de cacería esquelético", itIT = "Raptor da Caccia Scheletrico", zhTW = "骷髏狩獵迅猛龍" },
    [137591] = { enUS = "Healing Tide Totem", koKR = "치유의 해일 토템", frFR = "Totem de marée de soins", deDE = "Totem der Heilungsflut", zhCN = "治疗之潮图腾", ptBR = "Totem de Maré Curativa", esES = "Tótem de marea de sanación", ruRU = "Тотем целительного прилива", esMX = "", itIT = "Totem della Marea Curativa", zhTW = "療癒之潮圖騰" },
    [137969] = { enUS = "Interment Construct", koKR = "매장된 피조물", frFR = "Assemblage funéraire", deDE = "Bestattungskonstrukt", zhCN = "葬礼构造体", ptBR = "Constructo de Inumação", esES = "Ensamblaje de sepelio", ruRU = "Погребальный голем", esMX = "Ensamblaje del sepelio", itIT = "Costrutto d'Internamento", zhTW = "埋葬的魔像" },
    [137989] = { enUS = "Embalming Fluid", koKR = "불변의 액체", frFR = "Fluide d'embaumement", deDE = "Balsamierungsflüssigkeit", zhCN = "防腐液", ptBR = "Fluido Embalsamador", esES = "Líquido de embalsamar", ruRU = "Бальзамировочный состав", esMX = "Líquido de embalsamar", itIT = "Fluido per Imbalsamazioni", zhTW = "防腐液" },
    [138250] = { enUS = "Pool of Darkness", koKR = "어둠의 웅덩이", frFR = "Nappe de ténèbres", deDE = "Lache der Dunkelheit", zhCN = "黑暗之池", ptBR = "Fonte das Trevas", esES = "Charco de oscuridad", ruRU = "Омут тьмы", esMX = "", itIT = "Pozza delle Tenebre", zhTW = "黑暗之池" },
    [138489] = { enUS = "Shadow of Zul", koKR = "줄의 그림자", frFR = "Ombre de Zul", deDE = "Zuls Schatten", zhCN = "祖尔之影", ptBR = "Sombra de Zul", esES = "Sombra de Zul", ruRU = "Тень Зула", esMX = "Sombra de Zul", itIT = "Ombra di Zul", zhTW = "祖爾之影" },
    [138493] = { enUS = "Minion of Zul", koKR = "줄의 수하", frFR = "Séide de Zul", deDE = "Diener von Zul", zhCN = "祖尔的爪牙", ptBR = "Lacaio de Zul", esES = "Esbirro de Zul", ruRU = "Прислужник Зула", esMX = "", itIT = "Servitore di Zul", zhTW = "祖爾之僕" },
    [139097] = { enUS = "Sandswept Marksman", koKR = "모래받이 명사수", frFR = "Tireur des sables", deDE = "Sandgepeitschter Schütze", zhCN = "卷沙神射手", ptBR = "Atirador Perito Areeiro", esES = "Tirador Arrasarenas", ruRU = "Песчаный стрелок", esMX = "", itIT = "Tiratore Sferzasabbia", zhTW = "荒漠神射手" },
    [139108] = { enUS = "Loose Spark", koKR = "풀려난 불꽃", frFR = "Etincelle résiduelle", deDE = "Entfesselter Funke", zhCN = "不羁的火花", ptBR = "Fagulha Solta", esES = "Chispa suelta", ruRU = "Мечущаяся искра", esMX = "", itIT = "Scintilla Smossa", zhTW = "飄散電光" },
    [139110] = { enUS = "Spark Channeler", koKR = "불꽃 역술사", frFR = "Canaliste d'étincelles", deDE = "Funkenkanalisierer", zhCN = "火花引导者", ptBR = "Canalizador de Centelhas Sombrio", esES = "Canalizador de chispas", ruRU = "Искротворец", esMX = "Canalizador de chispas", itIT = "Canalizzatore di Scintille", zhTW = "火花傳導者" },
    [139131] = { enUS = "Polarized Spire", koKR = "양극화된 첨탑", frFR = "Flèche polarisée", deDE = "Polarisierte Spitze", zhCN = "极化尖塔", ptBR = "Pináculo Polarizado", esES = "Aguja polarizada", ruRU = "Поляризованный шпиль", esMX = "", itIT = "Guglia Polarizzata", zhTW = "極化尖塔" },
    [139422] = { enUS = "Dutiful Tamer", koKR = "충직한 조련사", frFR = "Dompteur dévoué", deDE = "Pflichtbewusster Zähmer", zhCN = "尽职的驯兽师", ptBR = "Domador Diligente", esES = "Domador diligente", ruRU = "Старательный укротитель", esMX = "Domador obediente", itIT = "Domatore Diligente", zhTW = "盡責的馴蟲師" },
    [139425] = { enUS = "Brood Tender", koKR = "혈족 관리인", frFR = "Soigne-couvée", deDE = "Brutpfleger", zhCN = "育巢者", ptBR = "Conservador da Ninhada", esES = "Cuidador de linaje", ruRU = "Кормилец выводка", esMX = "Cuidador de linaje", itIT = "Curatore della Stirpe", zhTW = "後裔看管者" },
    [187894] = { enUS = "Infused Whelp", koKR = "주입된 새끼용", frFR = "Dragonnet imprégné", deDE = "Energieerfüllter Welpe", zhCN = "注能龙崽", ptBR = "Dragonete Imbuído", esES = "Cría imbuida", ruRU = "Заряженный дракончик", esMX = "Cría imbuida", itIT = "Draghetto Infuso", zhTW = "灌能幼龍" },
    [187897] = { enUS = "Defier Draghar", koKR = "반항자 드라가르", frFR = "Draghar dissident", deDE = "Trotzer Draghar", zhCN = "亵渎者德拉加尔", ptBR = "Drahar Desafiador", esES = "Desafiador Draghar", ruRU = "Драгхар Отрицатель", esMX = "Retador Draghar", itIT = "Draghar Sfidante", zhTW = "挑戰者德拉哈" },
    [187969] = { enUS = "Deepstone Earthshaper", koKR = "심해석 대지창조자", frFR = "Sculpte-terre pierre-profonde", deDE = "Tiefsteinerdformer", zhCN = "深石塑地者", ptBR = "Moldaterra Pedrafunda", esES = "Modelador de tierra Piedraprofunda", ruRU = "Глубиннокаменный ваятель земли", esMX = "Modelador de tierra piedraprofunda", itIT = "Forgiaterra di Pietrafonda", zhTW = "深岩塑地者" },
    [188011] = { enUS = "Earthbound Guardian", koKR = "대지결속 수호자", frFR = "Gardien lié à la terre", deDE = "Erdgebundener Wächter", zhCN = "缚地守护者", ptBR = "Guardião Terreno", esES = "Guardián vinculado a la tierra", ruRU = "Землеподобный страж", esMX = "Guardián vinculado a la tierra", itIT = "Guardiano Tellurico", zhTW = "地縛守護者" },
    [188067] = { enUS = "Flashfrost Chillweaver", koKR = "섬광서리 한기술사", frFR = "Tisse-glace givréclair", deDE = "Blitzfrostkühlweber", zhCN = "闪霜织寒者", ptBR = "Tecefrio Gelo Súbito", esES = "Tejefrío Raudoescarcha", ruRU = "Ткач Холода Морозной Вспышки", esMX = "Tejescarcha rayogélido", itIT = "Tessigelo Freddolesto", zhTW = "閃霜織寒者" },
    [188244] = { enUS = "Primal Juggernaut", koKR = "원시 강력거수", frFR = "Mastodonte primordial", deDE = "Urzeitlicher Koloss", zhCN = "原始主宰", ptBR = "Jaganata Primevo", esES = "Gigante primigenio", ruRU = "Изначальный исполин", esMX = "Coloso primigenio", itIT = "Mastodonte Primordiale", zhTW = "原始重戰士" },
    [188252] = { enUS = "Melidrussa Chillworn", koKR = "멜리드루사 칠원", frFR = "Mélidrussa Manteglace", deDE = "Melidrussa die Unterkühlte", zhCN = "梅莉杜莎·寒妆", ptBR = "Melidrussa Geladura", esES = "Melidrussa Ajafrío", ruRU = "Мелидрусса Истощенная Холодом", esMX = "Melidrussa Tejescarcha", itIT = "Melidrussa Gelolacero", zhTW = "梅莉卓沙‧寒磨" },
    [189232] = { enUS = "Kokia Blazehoof", koKR = "코키아 블레이즈후프", frFR = "Kokia Foulebraise", deDE = "Kokia Feuerhuf", zhCN = "柯姬雅·焰蹄", ptBR = "Kokia Patardida", esES = "Kokia Pezuña de Fuego", ruRU = "Кокия Пламенное Копыто", esMX = "Kokia Pezuña Ardiente", itIT = "Kokia Zoccolo Ardente", zhTW = "可幾亞‧焰蹄" },
    [189886] = { enUS = "Blazebound Firestorm", koKR = "화염결속 불꽃폭풍", frFR = "Tempête braseliée", deDE = "Lohengebundener Feuersturm", zhCN = "炎缚火焰风暴", ptBR = "Tempestade de Fogo Presa às Chamas", esES = "Tormenta de Fuego vinculada a las llamas", ruRU = "Шторм бушующего пламени", esMX = "", itIT = "Tempesta di Fuoco Fiammante", zhTW = "炎縛火焰風暴" },
    [189893] = { enUS = "Infused Whelp", koKR = "주입된 새끼용", frFR = "Dragonnet imprégné", deDE = "Energieerfüllter Welpe", zhCN = "注能龙崽", ptBR = "Dragonete Imbuído", esES = "Cría imbuida", ruRU = "Заряженный дракончик", esMX = "", itIT = "Draghetto Infuso", zhTW = "灌能幼龍" },
    [190034] = { enUS = "Blazebound Destroyer", koKR = "화염결속 파괴자", frFR = "Destructeur braselié", deDE = "Lohengebundener Zerstörer", zhCN = "炎缚毁灭者", ptBR = "Destruidor Preso às Chamas", esES = "Destructor vinculado a las llamas", ruRU = "Пламенный разрушитель", esMX = "Destructor lazollama", itIT = "Distruttore Fiammante", zhTW = "火縛毀滅者" },
    [190205] = { enUS = "Scorchling", koKR = "불덩이", frFR = "Brûletin", deDE = "Flämmling", zhCN = "灼烧元素", ptBR = "Chamusquito", esES = "Agostizo", ruRU = "Сполох", esMX = "Agostizo", itIT = "Fiammetta", zhTW = "小焦焰" },
    [190206] = { enUS = "Ashseer Flamelasher", koKR = "잿빛선견자 화염채찍", frFR = "Prophète des cendres cingleflamme", deDE = "Flammenpeitscher der Aschenseher", zhCN = "灰烬先知烈焰鞭笞者", ptBR = "Fogaçoitador Vaticinza", esES = "Latifogador contemplacenizas", ruRU = "Пеплозрящий огнехлестатель", esMX = "Azotellamas vidente cinéreo", itIT = "Veggente Cinereo Sferzafiamme", zhTW = "灰燼焰笞者" },
    [190207] = { enUS = "Primalist Cinderweaver", koKR = "원시술사 잿불술사", frFR = "Tisse-cendre primaliste", deDE = "Glutweber der Primalisten", zhCN = "拜荒织烬者", ptBR = "Tecebrasas Primevista", esES = "Primalista tejecinéreo", ruRU = "Пеплоплет воинов стихий", esMX = "Tejecenizas primalista", itIT = "Tessicenere Primalista", zhTW = "洪荒使者織燼者" },
    [190484] = { enUS = "Kyrakka", koKR = "카이락카", frFR = "Kyrakka", deDE = "Kyrakka", zhCN = "基拉卡", ptBR = "Kyrakka", esES = "Kyrakka", ruRU = "Киракка", esMX = "Kyrakka", itIT = "Kyrakka", zhTW = "凱拉卡" },
    [190485] = { enUS = "Erkhart Stormvein", koKR = "에크하트 스톰베인", frFR = "Erkhart Foudreveine", deDE = "Erkhart Sturmader", zhCN = "厄克哈特·风脉", ptBR = "Erkhart Vendaveia", esES = "Erkhart Venatormenta", ruRU = "Эркхарт Кровь Бури", esMX = "Erkhart Sangre Tormentosa", itIT = "Erkhart Venariosa", zhTW = "俄克哈‧風脈" },
    [194622] = { enUS = "Scorchling", koKR = "불덩이", frFR = "Brûletin", deDE = "Flämmling", zhCN = "灼烧元素", ptBR = "Chamusquito", esES = "Agostizo", ruRU = "Сполох", esMX = "", itIT = "Fiammetta", zhTW = "小焦焰" },
    [195119] = { enUS = "Ruinous Stormbringer", koKR = "황폐의 폭풍인도자", frFR = "Porte-tempête dévastateur", deDE = "Ruinöser Sturmbringer", zhCN = "毁灭唤风者", ptBR = "Traztormenta Ruinoso", esES = "Invocatormentas ruinoso", ruRU = "Губительный вестник шторма", esMX = "Extiendetormentas ruinoso", itIT = "Araldo della Tempesta Rovinoso", zhTW = "荒殘風暴使者" },
    [197509] = { enUS = "Primal Thundercloud", koKR = "원시 뇌운", frFR = "Nuage d'orage primordial", deDE = "Urdonnerwolke", zhCN = "原始雷云", ptBR = "Nuvem de Tempestade Primeva", esES = "Cumulonimbo primigenio", ruRU = "Изначальная грозовая туча", esMX = "Nimbo primigenio", itIT = "Nube Tonante Primordiale", zhTW = "洪荒雷雲" },
    [197535] = { enUS = "High Channeler Ryvati", koKR = "고위 역술사 라이바티", frFR = "Haute invocatrice Ryvati", deDE = "Oberste Kanalisiererin Ryvati", zhCN = "大引导者莱瓦迪", ptBR = "Grã Canalizadora Ryvati", esES = "Alta canalizadora Ryvati", ruRU = "Верховная чаротворица Ривати", esMX = "Suma canalizadora Ryvati", itIT = "Alta Canalizzatrice Ryvati", zhTW = "大導魔師萊瓦蒂" },
    [197697] = { enUS = "Flamegullet", koKR = "불꽃탐식자", frFR = "Gorge-de-feu", deDE = "Feuerschlund", zhCN = "烈焰之咽", ptBR = "Goela Flamejante", esES = "Gargantardiente", ruRU = "Огнезев", esMX = "Pirogarganta", itIT = "Trincafiamme", zhTW = "火喉" },
    [197698] = { enUS = "Thunderhead", koKR = "천둥뿔도마뱀", frFR = "Tête-tonnerre", deDE = "Donnerkopf", zhCN = "雷霆之颅", ptBR = "Cabeça-de-trovão", esES = "Tronatesta", ruRU = "Громоголов", esMX = "Tronatesta", itIT = "Cumulonembo", zhTW = "雷首蜥蜴" },
    [197982] = { enUS = "Storm Warrior", koKR = "폭풍 전사", frFR = "Guerrier des tempêtes", deDE = "Sturmkrieger", zhCN = "风暴战士", ptBR = "Guerreiro da Tempestade", esES = "Guerrero de la tormenta", ruRU = "Воин бури", esMX = "Guerrero de tormenta", itIT = "Guerriero della Tempesta", zhTW = "風暴戰士" },
    [198047] = { enUS = "Tempest Channeler", koKR = "폭풍우의 역술사", frFR = "Invocatrice de tempêtes", deDE = "Sturmkanalisiererin", zhCN = "暴风引导者", ptBR = "Canalizadora de Tormenta", esES = "Canalizadora de la tempestad", ruRU = "Чаротворица бури", esMX = "Canalizadora de tempestades", itIT = "Canalizzatore della Tempesta", zhTW = "暴風導魔師" },
    [234647] = { enUS = "Xathuux the Annihilator", koKR = "파멸자 자투스", frFR = "Xathuux l'Annihilateur", deDE = "Xathuux der Vernichter", zhCN = "歼灭者萨祖克斯", ptBR = "Xathuux, o Aniquilador", esES = "Xathuux el Aniquilador", ruRU = "Затуукс Разрушитель", esMX = "", itIT = "Xathuux l'Annientatore", zhTW = "『殲滅者』薩索克斯" },
    [234648] = { enUS = "Kystia Manaheart", koKR = "키스티아 마나하트", frFR = "Kystia Coeur-de-Mana", deDE = "Kystia Manaherz", zhCN = "凯斯媞亚·魔力之心", ptBR = "Kystia Manacárdia", esES = "Kystia Manaudaz", ruRU = "Кистия Сердце Маны", esMX = "", itIT = "Kystia Manacuore", zhTW = "克絲提雅‧法心" },
    [234649] = { enUS = "Zaen Bladesorrow", koKR = "자엔 블레이드소로우", frFR = "Zaen Tristelame", deDE = "Zaen Klingentrauer", zhCN = "赞恩·刃悲", ptBR = "Zaen Laminúrio", esES = "Zaen Hojapena", ruRU = "Заэн Траурный Клинок", esMX = "", itIT = "Zaen Dololama", zhTW = "贊恩‧刃悲" },
    [234660] = { enUS = "Nibbles", koKR = "냠냠이", frFR = "Mordicus", deDE = "Knurps", zhCN = "咬咬", ptBR = "Mordisco", esES = "Dentellón", ruRU = "Грызунчик", esMX = "", itIT = "Vilmordino", zhTW = "尼波斯" },
    [234763] = { enUS = "Lithiel Cinderfury", koKR = "리시엘 신더퓨리", frFR = "Lithiel Fureur-de-Cendre", deDE = "Lithiel Glutzorn", zhCN = "利希尔·烬怒", ptBR = "Lithiel Brasafúria", esES = "Lithiel Ciniracunda", ruRU = "Литиэль Пепельная Ярость", esMX = "", itIT = "Lithiel Cenerfuria", zhTW = "莉希爾‧燼怒" },
    [234799] = { enUS = "Furious Vilefiend", koKR = "사나운 썩은마귀", frFR = "Démon abject furieux", deDE = "Zorniges Scheusal", zhCN = "狂怒的邪犬", ptBR = "Diabo Vil Furioso", esES = "Maligno vil furioso", ruRU = "Неистовый мерзотень", esMX = "", itIT = "Demonio Vile Furioso", zhTW = "狂怒邪惡犬魔" },
    [234849] = { enUS = "Unleashed Imp", koKR = "해방된 임프", frFR = "Diablotin déchaîné", deDE = "Entfesselter Wichtel", zhCN = "不羁的小鬼", ptBR = "Diabrete Liberto", esES = "Diablillo desatado", ruRU = "Натравленный бес", esMX = "Diablillo liberado", itIT = "Imp Scatenato", zhTW = "無拘小鬼" },
    [234852] = { enUS = "Forbidden Freight", koKR = "금지된 화물", frFR = "Cargaison interdite", deDE = "Verbotene Fracht", zhCN = "违禁的货物", ptBR = "Carga Proibida", esES = "Flete Prohibido", ruRU = "Запретный груз", esMX = "", itIT = "Merce Proibita", zhTW = "禁忌運輸" },
    [234860] = { enUS = "Crate Loader", koKR = "상자 운반꾼", frFR = "Débardeur de caisses", deDE = "Kistenverlader", zhCN = "装箱工", ptBR = "Carregador de Caixotes", esES = "Cargador de cajones", ruRU = "Погрузчик ящиков", esMX = "", itIT = "Caricatore di Casse", zhTW = "木箱裝貨員" },
    [234984] = { enUS = "Silvermoon Patron", koKR = "실버문 손님", frFR = "Client de Lune-d'Argent", deDE = "Silbermondgast", zhCN = "银月城主顾", ptBR = "Cliente de Luaprata", esES = "Cliente de Lunargenta", ruRU = "Гость Луносвета", esMX = "", itIT = "Cliente di Lunargenta", zhTW = "銀月城顧客" },
    [235257] = { enUS = "Demon Fly", koKR = "악마 비행가오리", frFR = "Aile démoniaque", deDE = "Dämonenflatterer", zhCN = "魔蝇", ptBR = "Mosca-demônio", esES = "Mosca demoníaca", ruRU = "Демоническая муха", esMX = "Mosca demoníaca", itIT = "Mosca Demoniaca", zhTW = "魔翼" },
    [235261] = { enUS = "Trained Felhunter", koKR = "조련된 지옥사냥개", frFR = "Chasseur corrompu dressé", deDE = "Ausgebildeter Teufelsjäger", zhCN = "驯服的地狱猎犬", ptBR = "Caçador Vil Treinado", esES = "Manáfago adiestrado", ruRU = "Дрессированный охотник Скверны", esMX = "Manáfago entrenado", itIT = "Vilsegugio Addestrato", zhTW = "經過訓練的惡魔獵犬" },
    [235265] = { enUS = "Corrupted Warlock", koKR = "타락한 흑마법사", frFR = "Démoniste corrompu", deDE = "Verderbter Hexenmeister", zhCN = "腐化的术士", ptBR = "Bruxo Corrompido", esES = "Brujo corrupto", ruRU = "Порабощенный чернокнижник", esMX = "Brujo corrompido", itIT = "Stregone Corrotto", zhTW = "腐化術士" },
    [235267] = { enUS = "Wrathguard Flayer", koKR = "격노수호병 약탈자", frFR = "Ecorcheur garde-courroux", deDE = "Schinder der Zornwächter", zhCN = "愤怒卫士掠夺者", ptBR = "Guardião Colérico Rancapele", esES = "Despellejador guardia de cólera", ruRU = "Страж гнева – живодер", esMX = "Guardia de cólera despellejador", itIT = "Guardia dell'Ira Scorticatrice", zhTW = "憤怒守衛撕掠者" },
    [235268] = { enUS = "Fel Invoker", koKR = "지옥 기원사", frFR = "Invocatrice gangrenée", deDE = "Teuflische Invokatorin", zhCN = "邪能祈求者", ptBR = "Evocadora Vil", esES = "Invocadora vil", ruRU = "Заклинатель Скверны", esMX = "Invocador vil", itIT = "Vilinvocatrice", zhTW = "魔化塑能師" },
    [235322] = { enUS = "Defiled Golem", koKR = "더럽혀진 골렘", frFR = "Golem profané", deDE = "Entweihter Golem", zhCN = "亵渎傀儡", ptBR = "Golem Profanado", esES = "Gólem profanado", ruRU = "Оскверненный голем", esMX = "Gólem profanado", itIT = "Golem Profanato", zhTW = "污穢魔像" },
    [235465] = { enUS = "Shivan Punisher", koKR = "쉬반 응징자", frFR = "Punisseuse shivane", deDE = "Bestraferin der Shivan", zhCN = "破坏魔惩罚者", ptBR = "Castigadora Shivânica", esES = "Castigadora shivaísta", ruRU = "Шиварра-карательница", esMX = "Castigadora shivaísta", itIT = "Punitrice Shivan", zhTW = "女妖懲戒者" },
    [235520] = { enUS = "Legion Axe", koKR = "군단 도끼", frFR = "Hache de la Légion", deDE = "Legionsaxt", zhCN = "军团大斧", ptBR = "Machado da Legião", esES = "Hacha de la Legión", ruRU = "Топор Легиона", esMX = "", itIT = "Ascia della Legione", zhTW = "軍團之斧" },
    [235841] = { enUS = "Selenar Sunshy", koKR = "셀레나르 선샤이", frFR = "Sélénar Soléclipse", deDE = "Selenar Sonnenscheu", zhCN = "赛勒纳·避日", ptBR = "Selenar Aversolis", esES = "Selenar Cohibisol", ruRU = "Селенар Смиренное Солнце", esMX = "", itIT = "Selenar Soleschivo", zhTW = "瑟雷納‧日羞" },
    [236071] = { enUS = "Bribed Guard", koKR = "매수된 경비병", frFR = "Garde soudoyé", deDE = "Bestochene Wache", zhCN = "被买通的守卫", ptBR = "Guarda Corrupto", esES = "Guardia sobornado", ruRU = "Подкупленный стражник", esMX = "Guardia sobornado", itIT = "Guardia Corrotta", zhTW = "受賄的守衛" },
    [236073] = { enUS = "Row Hooligan", koKR = "거리 난동꾼", frFR = "Voyou de l'allée", deDE = "Gassenschläger", zhCN = "径巷流氓", ptBR = "Baderneiro da Travessa", esES = "Gamberro del Frontal", ruRU = "Хулиган из Закоулка", esMX = "Rufián del Frontal", itIT = "Vandalo della Traversa", zhTW = "兇殺路流氓" },
    [236082] = { enUS = "Seductive Sayaad", koKR = "고혹적인 세이야드", frFR = "Sayaad séductrice", deDE = "Verführerische Sayaad", zhCN = "诱惑的萨亚德", ptBR = "Sayaad Sedutora", esES = "Sayaad seductora", ruRU = "Сайаад-соблазнительница", esMX = "Sayaad seductor", itIT = "Sayaad Seduttiva", zhTW = "誘人的薩亞德" },
    [236084] = { enUS = "Felonious Mage", koKR = "흉악한 마법사", frFR = "Mage félon", deDE = "Teufelsmagier", zhCN = "凶邪的法师", ptBR = "Mago Criminoso", esES = "Mago de vileza", ruRU = "Бесчестный маг", esMX = "Mago malhechor", itIT = "Mago Criminale", zhTW = "魔能法師" },
    [236085] = { enUS = "Felwyrm", koKR = "지옥지룡", frFR = "Wyrm gangrené", deDE = "Teufelswyrm", zhCN = "邪能浮龙", ptBR = "Moreia Vil", esES = "Vermivil", ruRU = "Змей Скверны", esMX = "Vermis vil", itIT = "Vildragone", zhTW = "魔化龍鰻" },
    [236088] = { enUS = "Masked Noble", koKR = "가면 쓴 귀족", frFR = "Noble masqué", deDE = "Maskierter Adliger", zhCN = "蒙面贵族", ptBR = "Nobre Mascarado", esES = "Noble enmascarado", ruRU = "Неизвестный аристократ", esMX = "", itIT = "Nobile Mascherato", zhTW = "假面貴族" },
    [236091] = { enUS = "Street Sneak", koKR = "길거리 은신자", frFR = "Rôdeur des rues", deDE = "Straßenschleicher", zhCN = "街头扒手", ptBR = "Pilantra de Rua", esES = "Acechador callejero", ruRU = "Уличный жулик", esMX = "Merodeador callejero", itIT = "Furfante di Strada", zhTW = "街頭潛行者" },
    [236525] = { enUS = "Rowdy Patron", koKR = "날뛰는 손님", frFR = "Client chahuteur", deDE = "Rüpelhafter Gast", zhCN = "吵闹的主顾", ptBR = "Cliente Valentão", esES = "Cliente alborotador", ruRU = "Буйный посетитель", esMX = "", itIT = "Cliente Turbolento", zhTW = "喧嘩的顧客" },
    [236893] = { enUS = "Warehouse Worker", koKR = "물류 창고 일꾼", frFR = "Ouvrier de l'entrepôt", deDE = "Lagerhausarbeiter", zhCN = "仓库工人", ptBR = "Trabalhador do Armazém", esES = "Trabajador del almacén", ruRU = "Складской рабочий", esMX = "Trabajador de depósito", itIT = "Lavoratore del Magazzino", zhTW = "倉庫工人" },
    [236897] = { enUS = "Keen Taskmaster", koKR = "예리한 작업반장", frFR = "Sous-chef enthousiaste", deDE = "Eifriger Zuchtmeister", zhCN = "敏锐的监工", ptBR = "Capataz Afiado", esES = "Capataz agudo", ruRU = "Внимательный надсмотрщик", esMX = "Capataz atento", itIT = "Coordinatore Acuto", zhTW = "敏銳的監工" },
    [236902] = { enUS = "Massive Felwyrm", koKR = "거대한 지옥지룡", frFR = "Enorme wyrm gangrené", deDE = "Riesiger Teufelswyrm", zhCN = "巨大的邪能浮龙", ptBR = "Moreia Vil Gigantesca", esES = "Vermivil enorme", ruRU = "Огромный змей Скверны", esMX = "Vermis vil descomunal", itIT = "Vildragone Massiccio", zhTW = "巨型魔化龍鰻" },
    [236905] = { enUS = "Felmaster Lucsei", koKR = "지옥지배자 룩세이", frFR = "Maître de la gangrène Lucsei", deDE = "Dämonenmeister Lucsei", zhCN = "邪能主宰鲁科西", ptBR = "Mestre-vil Lucsei", esES = "Maestro vil Lucsei", ruRU = "Мастер Скверны Люксей", esMX = "Maestro vil Lucsei", itIT = "Vilmaestro Lucsei", zhTW = "惡魔領主盧賽" },
    [237626] = { enUS = "Wild Imp", koKR = "날뛰는 임프", frFR = "Diablotin sauvage", deDE = "Wildwichtel", zhCN = "野生小鬼", ptBR = "Diabrete Selvagem", esES = "Diablillo salvaje", ruRU = "Дикий бес", esMX = "", itIT = "Imp Selvaggio", zhTW = "狂野小鬼" },
    [238414] = { enUS = "Infernal", koKR = "지옥불정령", frFR = "Infernal", deDE = "Höllenbestie", zhCN = "地狱火", ptBR = "Infernal", esES = "Infernal", ruRU = "Инфернал", esMX = "", itIT = "Infernale", zhTW = "煉獄火" },
    [238883] = { enUS = "Dominated Brawler", koKR = "지배당한 싸움꾼", frFR = "Bastonneur dominé", deDE = "Beherrschter Kämpfer", zhCN = "被统御的斗士", ptBR = "Brigão Dominado", esES = "Camorrista dominado", ruRU = "Подчиненный буян", esMX = "Luchador sometido", itIT = "Lottatore Dominato", zhTW = "被統御的鬥士" },
    [238887] = { enUS = "Taz'Rah", koKR = "타즈라", frFR = "Taz'Rah", deDE = "Taz'Rah", zhCN = "塔兹拉尔", ptBR = "Taz'Rah", esES = "Taz'Rah", ruRU = "Таз'ра", esMX = "", itIT = "Taz'rah", zhTW = "塔茲拉" },
    [239008] = { enUS = "Atroxus", koKR = "아트로서스", frFR = "Atroxus", deDE = "Atroxus", zhCN = "阿特洛苏斯", ptBR = "Atroxus", esES = "Atroxus", ruRU = "Атрокс", esMX = "", itIT = "Atroxus", zhTW = "奧托薩斯" },
    [239070] = { enUS = "Toxic Creeper", koKR = "유독한 살금벌레", frFR = "Rampant toxique", deDE = "Giftiger Kriecher", zhCN = "剧毒蠕行者", ptBR = "Parasita Tóxico", esES = "Trepador nocivo", ruRU = "Токсичный ползун", esMX = "", itIT = "Strisciante Tossico", zhTW = "劇毒潛伏者" },
    [239167] = { enUS = "Charonus", koKR = "차로누스", frFR = "Charonus", deDE = "Charonus", zhCN = "煞戎努斯", ptBR = "Charonus", esES = "Caronus", ruRU = "Харон", esMX = "", itIT = "Charonus", zhTW = "查洛納斯" },
    [240289] = { enUS = "Nauseous Patron", koKR = "속이 메스꺼운 손님", frFR = "Client nauséeux", deDE = "Übelkeitsgeplagter Gast", zhCN = "作呕的主顾", ptBR = "Espectador Enjoado", esES = "Cliente mareado", ruRU = "Позеленевший посетитель", esMX = "", itIT = "Cliente Nauseato", zhTW = "覺得噁心的顧客" },
    [240681] = { enUS = "Eye of Sethraliss", koKR = "세스랄리스의 눈", frFR = "Oeil de Sephraliss", deDE = "Auge von Sethraliss", zhCN = "塞塔里斯之眼", ptBR = "Olho de Sethraliss", esES = "Ojo de Sethraliss", ruRU = "Глаз Сетралисс", esMX = "", itIT = "Occhio di Sethraliss", zhTW = "瑟沙利斯之眼" },
    [241496] = { enUS = "Enthralled Shaman", koKR = "마법에 걸린 주술사", frFR = "Chaman ensorcelé", deDE = "Bezauberter Schamane", zhCN = "被奴役的萨满", ptBR = "Xamã Enfeitiçado", esES = "Chamán hipnotizado", ruRU = "Порабощенный шаман", esMX = "Chamán fascinado", itIT = "Sciamano Ammaliato", zhTW = "被控制的薩滿" },
    [241805] = { enUS = "Avatar of Starvation", koKR = "기근의 화신", frFR = "Avatar de famine", deDE = "Avatar des Hungers", zhCN = "饥荒化身", ptBR = "Avatar da Inanição", esES = "Avatar de la inanición", ruRU = "Аватара голодной смерти", esMX = "", itIT = "Avatar della Fame", zhTW = "飢餓化身" },
    [241808] = { enUS = "Territorial Matriarch", koKR = "텃세하는 어미", frFR = "Matriarche territoriale", deDE = "Territoriale Matriarchin", zhCN = "领地主母", ptBR = "Matriarca Territorial", esES = "Matriarca territorial", ruRU = "Территориальный матриарх", esMX = "Matriarca territorial", itIT = "Matriarca Territoriale", zhTW = "衛地族母" },
    [241809] = { enUS = "Curious Yearling", koKR = "호기심 많은 어린 동물", frFR = "Jeune ours curieux", deDE = "Neugieriger Jährling", zhCN = "好奇的幼崽", ptBR = "Novilho Curioso", esES = "Cría curiosa", ruRU = "Любопытный первогодок", esMX = "", itIT = "Cucciolo Curioso", zhTW = "好奇的幼體" },
    [241812] = { enUS = "The Hoardmonger", koKR = "비축광", frFR = "Le Thésauriseur", deDE = "Der Hortraffer", zhCN = "囤宝狂人", ptBR = "O Acumulista", esES = "El Acaparatesoros", ruRU = "Прозапасник", esMX = "", itIT = "L'Accumulatore", zhTW = "囤積者" },
    [241813] = { enUS = "Thornclaw Gatherer", koKR = "가시발톱 채집가", frFR = "Récolteur griffépine", deDE = "Dornklauensammler", zhCN = "棘爪收集者", ptBR = "Coletador Garrespinho", esES = "Recolector garraspina", ruRU = "Шипокоготь-добытчик", esMX = "Recolector zarpaespina", itIT = "Raccoglitore Sfregiaspine", zhTW = "棘爪蒐集者" },
    [241814] = { enUS = "Earthwhisper Tender", koKR = "대지교감자 뜰지기", frFR = "Soigneur murmeterre", deDE = "Erdwisperhüter", zhCN = "地语看护者", ptBR = "Conservador Sussurraterra", esES = "Cuidador susurratierra", ruRU = "Землевещун-хранитель", esMX = "Cuidador susurratierra", itIT = "Curatore del Sussurro Terrestre", zhTW = "地語看管者" },
    [241816] = { enUS = "Keen-Eyed Striker", koKR = "눈썰미 좋은 격퇴자", frFR = "Frappeur oeil-de-lynx", deDE = "Wachsamer Angreifer", zhCN = "锐眼掠击鹰", ptBR = "Golpeador de Olho Afiado", esES = "Golpeador ojoagudo", ruRU = "Зоркий налетчик", esMX = "", itIT = "Assalitore Occhioacuto", zhTW = "銳眼打擊者" },
    [241869] = { enUS = "Avatar of Determination", koKR = "결의의 화신", frFR = "Avatar de détermination", deDE = "Avatar der Entschlossenheit", zhCN = "决意化身", ptBR = "Avatar da Determinação", esES = "Avatar de la determinación", ruRU = "Аватара решимости", esMX = "Avatar de determinación", itIT = "Avatar della Determinazione", zhTW = "決心化身" },
    [241872] = { enUS = "Frigid Mauler", koKR = "혹한의 싸움꾼", frFR = "Marteleur algide", deDE = "Eisiger Zermalmer", zhCN = "酷寒重殴者", ptBR = "Espancador Frígido", esES = "Aplastador gélido", ruRU = "Морозный терзатель", esMX = "Magullador frígido", itIT = "Mazzuolatore Gelido", zhTW = "嚴寒重槌熊" },
    [241874] = { enUS = "Frostfang", koKR = "서리송곳니", frFR = "Croc-de-givre", deDE = "Frostfangzahn", zhCN = "霜牙", ptBR = "Presa Gélida", esES = "Colmihielo", ruRU = "Хладоклык", esMX = "Colmihielo", itIT = "Unghiagelata", zhTW = "霜牙" },
    [241876] = { enUS = "Glacial Revenant", koKR = "빙하의 망령", frFR = "Revenant glaciaire", deDE = "Gletscherklagegeist", zhCN = "冰川亡魂", ptBR = "Assombração Glacial", esES = "Aparecido glacial", ruRU = "Ледниковый загробник", esMX = "Aparecido glacial", itIT = "Spettro Glaciale", zhTW = "冰川亡魄" },
    [241911] = { enUS = "Terra Rumbler", koKR = "대지 우레정령", frFR = "Grondeur de Terra", deDE = "Terrarumpler", zhCN = "撼地奔行者", ptBR = "Estrondor Terra", esES = "Terraestruendor", ruRU = "Землистый грохотун", esMX = "Estruendor de terra", itIT = "Elementale Tellurico della Terra", zhTW = "大地震盪者" },
    [243028] = { enUS = "Meittik", koKR = "메이티크", frFR = "Meittik", deDE = "Meittik", zhCN = "梅提克", ptBR = "Meittik", esES = "Meittik", ruRU = "Мейттик", esMX = "", itIT = "Meittik", zhTW = "梅提克" },
    [243029] = { enUS = "Kezkitt", koKR = "케즈키트", frFR = "Kezkitt", deDE = "Kezkitt", zhCN = "科兹齐特", ptBR = "Kezkitt", esES = "Kezkitt", ruRU = "Кезкитт", esMX = "", itIT = "Kezkitt", zhTW = "科基特" },
    [243030] = { enUS = "Lekshi", koKR = "레크쉬", frFR = "Lekshi", deDE = "Lekshi", zhCN = "莱克希", ptBR = "Lekshi", esES = "Lekshi", ruRU = "Лекши", esMX = "", itIT = "Lekshi", zhTW = "雷克席" },
    [243736] = { enUS = "Blistercreep", koKR = "물집벌레", frFR = "Ectocloque", deDE = "Blasenkriecher", zhCN = "爆爬虫", ptBR = "Rastejolha", esES = "Ampollino", ruRU = "Огнежальщик", esMX = "Alimallaga", itIT = "Scarabolla", zhTW = "發泡蠕行蟲" },
    [243766] = { enUS = "Kilivore Screamer", koKR = "킬리보어 비명꾼", frFR = "Mortivore hurleur", deDE = "Kreischer der Totfresser", zhCN = "千噬兽尖啸者", ptBR = "Urrador Kilívoro", esES = "Vociferador kilívoro", ruRU = "Килижор-крикун", esMX = "Vociferador mortívoro", itIT = "Kilivoro Urlatore", zhTW = "噬殺蟲尖嘯者" },
    [243835] = { enUS = "Savage Shredclaw", koKR = "야만적인 서슬발톱", frFR = "Griffentaille sauvage", deDE = "Unbändige Schredderklaue", zhCN = "野蛮裂爪兽", ptBR = "Garrasga Selvagem", esES = "Triturazarpa salvaje", ruRU = "Свирепый саблекоготь", esMX = "Trizagarras salvaje", itIT = "Lacerartiglio Selvaggio", zhTW = "蠻野碎爪" },
    [243983] = { enUS = "Sycophantic Tarasek", koKR = "아첨꾼 타라세크", frFR = "Tarasèke servile", deDE = "Kriecherischer Tarasek", zhCN = "谄媚的塔拉赛", ptBR = "Tarasek Bajulador", esES = "Tarasek servil", ruRU = "Тарасекк-приспешник", esMX = "Tarasek servil", itIT = "Tarasek Servile", zhTW = "諂媚的塔拉賽克" },
    [243985] = { enUS = "Longtooth Tuskarr", koKR = "긴이빨 투스카르", frFR = "Rohart longues-dents", deDE = "Langzahntuskarr", zhCN = "长牙海象人", ptBR = "Morsano Longodente", esES = "Colmillarr Dientelargo", ruRU = "Клыкарр-длиннозуб", esMX = "Colmillarr dientelargo", itIT = "Tuskarr Lungazanna", zhTW = "長牙巨牙海民" },
    [243988] = { enUS = "Feral Saberon", koKR = "야성 서슬니", frFR = "Sabron farouche", deDE = "Wilder Saberon", zhCN = "狂野的刃牙虎人", ptBR = "Saberon Feral", esES = "Sablerón salvaje", ruRU = "Дикий саблерон", esMX = "Saberon salvaje", itIT = "Saberon Feroce", zhTW = "兇狠的劍齒人" },
    [243996] = { enUS = "Lost Sethrak", koKR = "길 잃은 세스락", frFR = "Sephrak perdu", deDE = "Verirrter Sethrak", zhCN = "迷失的蛇人", ptBR = "Sethrak Perdido", esES = "Sethrak perdido", ruRU = "Потерянный сетрак", esMX = "Sethrak perdido", itIT = "Sethrak Perduto", zhTW = "迷路的塞斯拉克" },
    [244100] = { enUS = "Sentinel of Winter", koKR = "겨울의 파수꾼", frFR = "Sentinelle de l'hiver", deDE = "Winterwache", zhCN = "寒冬哨兵", ptBR = "Sentinela do Inverno", esES = "Centinela del invierno", ruRU = "Часовой зимы", esMX = "", itIT = "Sentinella dell'Inverno", zhTW = "凜冬哨兵" },
    [244260] = { enUS = "Chitigoth", koKR = "키티고스", frFR = "Chitigoth", deDE = "Chitigoth", zhCN = "几丁高斯", ptBR = "Chitigoth", esES = "Chitigoth", ruRU = "Читигот", esMX = "Chitigoth", itIT = "Chitigoth", zhTW = "奇提戈斯" },
    [244309] = { enUS = "Brutok", koKR = "브루톡", frFR = "Brutok", deDE = "Brutok", zhCN = "布鲁托克", ptBR = "Brutok", esES = "Brutok", ruRU = "Бруток", esMX = "Brutok", itIT = "Brutok", zhTW = "布魯托克" },
    [244528] = { enUS = "Lightblossom", koKR = "빛송이", frFR = "Lumiflore", deDE = "Lichtblume", zhCN = "光明之花", ptBR = "Botão de Luz", esES = "Flor de luz", ruRU = "Блескоцвет", esMX = "", itIT = "Fiordiluce", zhTW = "聖光花" },
    [244696] = { enUS = "Raging Squall", koKR = "분노하는 돌풍", frFR = "Ouragan déchaîné", deDE = "Wütender Sturm", zhCN = "狂怒的飑风", ptBR = "Borrasca Selvagem", esES = "Borrasca enfurecida", ruRU = "Дикий шквал", esMX = "", itIT = "Burrasca Furente", zhTW = "狂怒疾風" },
    [244708] = { enUS = "Voidminder", koKR = "공허주시자", frFR = "Factotum du Néant", deDE = "Leerenaufpasser", zhCN = "虚空看顾者", ptBR = "Mentalizador do Caos", esES = "Cuidador del Vacío", ruRU = "Смотритель Бездны", esMX = "Escoltavacío", itIT = "Guardiano del Vuoto", zhTW = "虛無控制者" },
    [244759] = { enUS = "Fractured Shivercore", koKR = "조각난 혹한핵", frFR = "Frémicoeur fracturé", deDE = "Gebrochener Zitterkern", zhCN = "碎裂的震颤核心", ptBR = "Gelinúcleo Fraturado", esES = "Temblonúcleo fracturado", ruRU = "Расколотый озноб-камень", esMX = "", itIT = "Nucleo Tremante Infranto", zhTW = "碎裂冷顫核心" },
    [244887] = { enUS = "Ikuzz the Light Hunter", koKR = "빛 사냥꾼 이쿠즈", frFR = "Chasselumière Ikuzz", deDE = "Ikuzz der Lichtjäger", zhCN = "圣光猎手伊库兹", ptBR = "Ikanz, o Caça-luz", esES = "Ikuzz el cazador de Luz", ruRU = "Икузз Охотник Света", esMX = "", itIT = "Ikuzz il Cacciatore di Luce", zhTW = "『聖光獵人』伊庫茲" },
    [244889] = { enUS = "Loa Speaker Nanea", koKR = "로아 전령 나네아", frFR = "Parle-loa Nanéa", deDE = "Loasprecherin Nanea", zhCN = "神灵代言人纳尼亚", ptBR = "Voz-dos-loas Nanea", esES = "Portavoz de loa Nanea", ruRU = "Говорящая с лоа Нанея", esMX = "", itIT = "Oratrice dei Loa Nanea", zhTW = "羅亞語者娜妮" },
    [245076] = { enUS = "The Pale Eye", koKR = "창백한 눈", frFR = "L'Oeil pâle", deDE = "Das Blasse Auge", zhCN = "苍白之眼", ptBR = "O Olho Pálido", esES = "El Ojo Pálido", ruRU = "Бледное око", esMX = "", itIT = "Occhio Pallido", zhTW = "蒼白之眼" },
    [245139] = { enUS = "Stormbound Mystic", koKR = "폭풍결속 비술사", frFR = "Mystique liée à la tempête", deDE = "Sturmgebundene Mystikerin", zhCN = "雷缚秘法师", ptBR = "Mística Tempestuosa", esES = "Mística vinculada a la tormenta", ruRU = "Скованный мистик бури", esMX = "Mística lazotormenta", itIT = "Mistica Tempestosa", zhTW = "颶縛秘術使" },
    [245143] = { enUS = "Ruthless Totemcaller", koKR = "무자비한 토템소환사", frFR = "Mande-totem impitoyable", deDE = "Skrupelloser Totemrufer", zhCN = "冷酷的图腾召唤者", ptBR = "Evocador de Totens Implacável", esES = "Clamatótems implacable", ruRU = "Безжалостный заклинатель тотемов", esMX = "Clamatótems despiadado", itIT = "Invocatotem Crudele", zhTW = "無情圖騰呼喚者" },
    [245145] = { enUS = "Bonded Beasttamer", koKR = "결속된 야수조련사", frFR = "Dompteur de bêtes lié", deDE = "Gebundener Tierzähmer", zhCN = "羁绊驯兽师", ptBR = "Doma-feras Vinculado", esES = "Domador de bestias vinculado", ruRU = "Верный укротитель", esMX = "Domador de bestias probado", itIT = "Allevatore Vincolato", zhTW = "締約馴獸師" },
    [245146] = { enUS = "Grizzled Warbringer", koKR = "성난 전쟁인도자", frFR = "Porteguerre aguerri", deDE = "Ergrauter Kriegstreiber", zhCN = "老练的战争使者", ptBR = "Armipotente Veterano", esES = "Belisario curtido", ruRU = "Седой вестник войны", esMX = "Belisaria grisácea", itIT = "Aralda della Guerra Veterana", zhTW = "老練的戰爭使者" },
    [245148] = { enUS = "Grizzled Warbringer", koKR = "성난 전쟁인도자", frFR = "Porteguerre aguerrie", deDE = "Ergraute Kriegstreiberin", zhCN = "老练的战争使者", ptBR = "Armipotente Veterana", esES = "Belisaria curtida", ruRU = "Седая вестница войны", esMX = "", itIT = "Aralda della Guerra Veterana", zhTW = "老練的戰爭使者" },
    [245190] = { enUS = "Loyal Saberfang", koKR = "충직한 사브르송곳니", frFR = "Sabrecroc fidèle", deDE = "Treuer Säbelzahn", zhCN = "忠诚的刃牙山猫", ptBR = "Presa-de-sabre Leal", esES = "Colmillo de sable leal", ruRU = "Верный саблеклык", esMX = "", itIT = "Zannamozza Leale", zhTW = "忠誠的刃牙" },
    [245336] = { enUS = "Radiant Spellsower", koKR = "찬란한 주문파종꾼", frFR = "Sème-sorts radieux", deDE = "Strahlender Zaubersäer", zhCN = "光耀播法者", ptBR = "Feiticícola Resplandecente", esES = "Siembrahechizos radiante", ruRU = "Сияющий чаросеятель", esMX = "Siembrahechizos radiante", itIT = "Seminamagia Radioso", zhTW = "聖輝播法者" },
    [245339] = { enUS = "Underbrush Stalker", koKR = "수풀 추적자", frFR = "Traqueur des broussailles", deDE = "Unterholzpirscher", zhCN = "灌林追猎者", ptBR = "Espreitador da Relva", esES = "Acechador de la maleza", ruRU = "Лесной ловец", esMX = "Acechador de maleza", itIT = "Inseguitore del Sottobosco", zhTW = "草叢潛獵者" },
    [245345] = { enUS = "Lightgorged Lasher", koKR = "빛포식 덩굴손", frFR = "Flagellant gorgé de lumière", deDE = "Lichtgesättigter Peitscher", zhCN = "光噬鞭笞者", ptBR = "Açoitadeira Empanturrada de Luz", esES = "Azotador atiborrado de Luz", ruRU = "Насыщенный Светом плеточник", esMX = "Azotador atiborrado de luz", itIT = "Pianta Sferzante Rimpinzata di Luce", zhTW = "光噬鞭笞者" },
    [245346] = { enUS = "Virid Grovekeeper", koKR = "신록의 숲감시자", frFR = "Surveille-bosquet viridien", deDE = "Grüner Hainhüter", zhCN = "翠绿林地守护者", ptBR = "Guarda-bosque de Virid", esES = "Guardia de la arboleda glauco", ruRU = "Изумрудный хранитель рощи", esMX = "Guardia de la arboleda viridiano", itIT = "Custode del Bosco Verdeggiante", zhTW = "翠綠林地守衛" },
    [245410] = { enUS = "Lasher", koKR = "덩굴손", frFR = "Flagellant", deDE = "Peitscher", zhCN = "鞭笞者", ptBR = "Açoitadeira", esES = "Azotador", ruRU = "Плеточник", esMX = "Azotador", itIT = "Pianta Sferzante", zhTW = "鞭笞者" },
    [245460] = { enUS = "Leafy Grovecrawler", koKR = "풀잎 숲포복자", frFR = "Rampant des bosquets feuillu", deDE = "Blättriger Hainkrabbler", zhCN = "多叶林莽爬行者", ptBR = "Rastejante do Bosque Folhoso", esES = "Reptarboledas frondoso", ruRU = "Лиственный ползун рощи", esMX = "Zancarboleda frondoso", itIT = "Strisciabosco Frondoso", zhTW = "青葉林地爬行者" },
    [245473] = { enUS = "Thorny Saptor", koKR = "가시 샙터", frFR = "Cédraptor épineux", deDE = "Dorniger Harzraptor", zhCN = "多刺的迅叶龙", ptBR = "Florráptor Espinhoso", esES = "Saptor espinoso", ruRU = "Шипастый фитоящер", esMX = "Plantor espinoso", itIT = "Raptolinfa Spinoso", zhTW = "棘刺樹液迅猛龍" },
    [245484] = { enUS = "Lightfeather Petalwing", koKR = "불빛깃털 꽃잎날개", frFR = "Folibri vive-plume", deDE = "Lichtfederblütenblattschwinge", zhCN = "光羽瓣翼鸟", ptBR = "Petalasa Penaleve", esES = "Alapétalo Plumagrácil", ruRU = "Легкоперый лепестокрыл", esMX = "Alapétalo de pluma ligera", itIT = "Alapetalo Piumasoffice", zhTW = "光羽瓣翼鳥" },
    [245513] = { enUS = "Overgrown Hydra", koKR = "비대해진 히드라", frFR = "Hydre géante", deDE = "Überwucherte Hydra", zhCN = "长得过大的多头花", ptBR = "Hidra Superdesenvolvida", esES = "Hidra desmesurada", ruRU = "Разросшаяся гидра", esMX = "Hidra descomunal", itIT = "Idra Ipertrofica", zhTW = "巨大的多頭樹妖" },
    [245527] = { enUS = "Spineshield Beetle", koKR = "가시방패 딱정벌레", frFR = "Hanneton broquéchine", deDE = "Stachelschildkäfer", zhCN = "脊盾甲虫", ptBR = "Besouro Espinoscudo", esES = "Alfazaque Escudoespinoso", ruRU = "Щитоспинный жук", esMX = "Alfazaque caparaespinas", itIT = "Scarabeo Scudospino", zhTW = "棘盾甲蟲" },
    [245567] = { enUS = "Starvation Effigy", koKR = "기근의 입상", frFR = "Effigie de famine", deDE = "Hungerbildnis", zhCN = "饥荒雕像", ptBR = "Efígie da Inanição", esES = "Efigie de inanición", ruRU = "Идол голода", esMX = "", itIT = "Effige della Fame", zhTW = "飢餓咒像" },
    [245752] = { enUS = "Keen-Eyed Striker", koKR = "눈썰미 좋은 격퇴자", frFR = "Frappeur oeil-de-lynx", deDE = "Wachsamer Angreifer", zhCN = "锐眼掠击鹰", ptBR = "Golpeador de Olho Afiado", esES = "Golpeador ojoagudo", ruRU = "Зоркий налетчик", esMX = "Golpeador ojoagudo", itIT = "Assalitore Occhioacuto", zhTW = "銳眼打擊者" },
    [245855] = { enUS = "Spirit of Hunger", koKR = "허기의 영혼", frFR = "Esprit de faim", deDE = "Geist des Hungers", zhCN = "饥渴之灵", ptBR = "Espírito da Fome", esES = "Espíritu de hambre", ruRU = "Дух голода", esMX = "Espíritu de hambre", itIT = "Spirito della Fame", zhTW = "飢餓之靈" },
    [245912] = { enUS = "Lightwarden Ruia", koKR = "빛의 감시자 루이아", frFR = "Gardelumière Ruia", deDE = "Lichthüter Ruia", zhCN = "护光者鲁伊亚", ptBR = "Guardião da Luz Ruia", esES = "Celador de la Luz Ruia", ruRU = "Страж Света Руйя", esMX = "", itIT = "Custode della Luce Ruia", zhTW = "護光者魯亞" },
    [245950] = { enUS = "Watchful Harrower", koKR = "감시하는 박해자", frFR = "Persécuteur vigilant", deDE = "Wachsamer Plager", zhCN = "警惕的掠心者", ptBR = "Consternador Vigilante", esES = "Lacerante atento", ruRU = "Бдительный боронитель", esMX = "Torturador vigilante", itIT = "Straziatore Vigile", zhTW = "警戒的哈洛爾" },
    [246367] = { enUS = "Spirit Bear", koKR = "영혼 곰", frFR = "Esprit de l'ours", deDE = "Geisterbär", zhCN = "幽灵熊", ptBR = "Espírito de Urso", esES = "Espíritu de oso", ruRU = "Дух медведя", esMX = "", itIT = "Orso Spiritico", zhTW = "靈魂熊" },
    [246371] = { enUS = "Spirit Moonkin", koKR = "영혼 달빛야수", frFR = "Esprit sélénien", deDE = "Geistermondkin", zhCN = "幽灵枭兽", ptBR = "Espírito de Luniscante", esES = "Lechúcico lunar espiritual", ruRU = "Призрачный совух", esMX = "", itIT = "Lunagufo Spiritico", zhTW = "靈魂梟獸" },
    [246404] = { enUS = "Nalorakk", koKR = "날로라크", frFR = "Nalorakk", deDE = "Nalorakk", zhCN = "纳洛拉克", ptBR = "Nalorakk", esES = "Nalorakk", ruRU = "Налоракк", esMX = "", itIT = "Nalorakk", zhTW = "納羅拉克" },
    [246409] = { enUS = "Zul'jarra", koKR = "줄자라", frFR = "Zul'jarra", deDE = "Zul'jarra", zhCN = "祖尔加拉", ptBR = "Zul'jarra", esES = "Zul'jarra", ruRU = "Зул'джарра", esMX = "", itIT = "Zul'jarra", zhTW = "祖爾賈拉" },
    [246591] = { enUS = "Glacial Tomb", koKR = "혹한의 무덤", frFR = "Tombe glaciale", deDE = "Gletschergrab", zhCN = "冰川之墓", ptBR = "Tumba Glacial", esES = "Tumba glacial", ruRU = "Ледяной склеп", esMX = "", itIT = "Tomba Glaciale", zhTW = "冰川之墓" },
    [246871] = { enUS = "Luminous Thornmaw", koKR = "빛나는 가시아귀", frFR = "Gueulépine lumineux", deDE = "Leuchtendes Dornenmaul", zhCN = "发光的棘喉兽", ptBR = "Gorjespinho Luminoso", esES = "Faucespino luminoso", ruRU = "Блистающий шипожор", esMX = "Faucespinas luminoso", itIT = "Faucirovo Luminoso", zhTW = "發光荊喉獸" },
    [247301] = { enUS = "Echo of Nalorakk", koKR = "날로라크의 메아리", frFR = "Echo de Nalorakk", deDE = "Echo von Nalorakk", zhCN = "纳洛拉克的回响", ptBR = "Eco de Nalorakk", esES = "Eco de Nalorakk", ruRU = "Эхо Налоракка", esMX = "", itIT = "Eco di Nalorakk", zhTW = "納羅拉克的回音" },
    [247676] = { enUS = "Ziekket", koKR = "지케트", frFR = "Ziekket", deDE = "Ziekket", zhCN = "兹欧凯特", ptBR = "Ziekket", esES = "Ziekket", ruRU = "Зиккет", esMX = "", itIT = "Ziekket", zhTW = "齊克特" },
    [247755] = { enUS = "Lightspawn Lasher", koKR = "빛의 태생 덩굴손", frFR = "Flagellant né de la lumière", deDE = "Lichtbrutpeitscher", zhCN = "光诞鞭笞者", ptBR = "Açoitadeira Cria da Luz", esES = "Azotador engendro de luz", ruRU = "Светорожденный плеточник", esMX = "", itIT = "Pianta Sferzante della Prole della Luce", zhTW = "光誕鞭笞者" },
    [248666] = { enUS = "Magma Totem", koKR = "용암 토템", frFR = "Totem de magma", deDE = "Magmatotem", zhCN = "熔岩图腾", ptBR = "Totem de Magma", esES = "Tótem de magma", ruRU = "Тотем магмы", esMX = "", itIT = "Totem del Magma", zhTW = "熔岩圖騰" },
    [249461] = { enUS = "Abducted Drakonid", koKR = "납치당한 용기병", frFR = "Drakônide enlevée", deDE = "Entführte Drakonide", zhCN = "被绑架的龙人", ptBR = "Draconídea Abduzida", esES = "Dracónido secuestrado", ruRU = "Похищенный драконид", esMX = "Dracónida raptada", itIT = "Draconide Rapita", zhTW = "被劫持的龍獸" },
    [249590] = { enUS = "Angry Krolusk", koKR = "성난 크롤러스크", frFR = "Krolusk colérique", deDE = "Wütender Krolusk", zhCN = "暴怒的三叶虫", ptBR = "Crolusco Raivoso", esES = "Crolusco enfadado", ruRU = "Злобный кролуск", esMX = "Krolusko enfadado", itIT = "Krolusk Furente", zhTW = "憤怒的葉殼蟲" },
    [249603] = { enUS = "Protective Turtle", koKR = "보호의 거북", frFR = "Tortue protectrice", deDE = "Beschützende Schildkröte", zhCN = "充满保护欲的乌龟", ptBR = "Tartaruga Protetora", esES = "Tortuga protectora", ruRU = "Черепаха-страж", esMX = "Tortuga protectora", itIT = "Tartaruga Protettiva", zhTW = "防護的烏龜" },
    [249608] = { enUS = "Raging Raptor", koKR = "거센 랩터", frFR = "Raptor déchaîné", deDE = "Wütender Raptor", zhCN = "暴怒的迅猛龙", ptBR = "Raptor Raivoso", esES = "Raptor furibundo", ruRU = "Ярый ящер", esMX = "Raptor enfurecido", itIT = "Raptor Furente", zhTW = "狂怒迅猛龍" },
    [249756] = { enUS = "Potatoad Matriarch", koKR = "감자꺼비 어미", frFR = "Matriarche terratracienne", deDE = "Krötoffelmatriarchin", zhCN = "薯身蟾主母", ptBR = "Matriarca Sapércula", esES = "Matriarca sapotata", ruRU = "Бульбожаба-матриарх", esMX = "Matriarca papasapo", itIT = "Matriarca Patarospo", zhTW = "馬鈴薯蟾蜍族母" },
    [249783] = { enUS = "Potadpole Egg", koKR = "감자올챙이 알", frFR = "Oeuf de tertard", deDE = "Krötoffelquappenei", zhCN = "薯身幼蟾卵", ptBR = "Ovo de Tubergirino", esES = "Huevo de renacuatata", ruRU = "Яйцо бульбожаблика", esMX = "", itIT = "Uovo di Patagirino", zhTW = "馬鈴薯蝌蚪卵" },
    [250202] = { enUS = "Newborn Potadpole", koKR = "새로 태어난 감자올챙이", frFR = "Tertard nourrisson", deDE = "Neugeborene Krötoffelquappe", zhCN = "新生的薯身幼蟾", ptBR = "Tubergirino Recém-nascido", esES = "Renacuatata recién nacida", ruRU = "Вылупившийся бульбожаблик", esMX = "", itIT = "Patagirino Neonato", zhTW = "新生的馬鈴薯蝌蚪" },
    [250478] = { enUS = "The Winter Squall", koKR = "겨울 돌풍", frFR = "La rafale hivernale", deDE = "Die Winterböe", zhCN = "寒冬暴风雪", ptBR = "A Rajada Invernal", esES = "La borrasca invernal", ruRU = "Зимний шквал", esMX = "La borrasca invernal", itIT = "Burrasca Invernale", zhTW = "凜冬狂風" },
    [251189] = { enUS = "Snow Orb Stalker", koKR = "눈의 보주 추적기", frFR = "Traqueur d'orbe neigeux", deDE = "Schneekugelpirscher", zhCN = "冰雪之珠追踪者", ptBR = "Espreitador do Orbe da Neve", esES = "Acechador de orbe de nieve", ruRU = "Ловец снежных шаров", esMX = "", itIT = "Inseguitore del Globo di Neve", zhTW = "雪球潛獵者" },
    [252041] = { enUS = "Satiated Avatar of Starvation", koKR = "만족한 기근의 화신", frFR = "Avatar de famine rassasié", deDE = "Gesättigter Avatar des Hungers", zhCN = "餍足的饥荒化身", ptBR = "Avatar da Inanição Saciado", esES = "Avatar de la inanición saciado", ruRU = "Насытившаяся аватара голодной смерти", esMX = "", itIT = "Avatar della Fame Sazio", zhTW = "滿足的飢餓化身" },
    [252053] = { enUS = "Brutal Overseer", koKR = "잔혹한 감독관", frFR = "Surveillant brute", deDE = "Brutaler Aufseher", zhCN = "鲁莽监督者", ptBR = "Supervisor Brutal", esES = "Sobrestante brutal", ruRU = "Жестокий надзиратель", esMX = "Sobrestante brutal", itIT = "Sovrintendente Brutale", zhTW = "殘酷監督者" },
    [252072] = { enUS = "Voidtouched Magi", koKR = "공허에 물든 마법사", frFR = "Magi touché par le Vide", deDE = "Leerenberührter Magier", zhCN = "虚触法师", ptBR = "Mago Maculado pelo Caos", esES = "Magi tocado por el Vacío", ruRU = "Зараженный Бездной колдун", esMX = "Magi tocado por el Vacío", itIT = "Mago Toccato dal Vuoto", zhTW = "虛無之觸魔導師" },
    [252508] = { enUS = "Scavenging Siphoid", koKR = "청소부 흡수체", frFR = "Siphoïde charognard", deDE = "Aasfressender Saugoid", zhCN = "食腐虹虚魔", ptBR = "Sifonoide Catador", esES = "Sifoide carroñero", ruRU = "Сифоноид-падальщик", esMX = "Sifoide carroñero", itIT = "Sifoide Saprofago", zhTW = "掠食刺水母" },
    [252529] = { enUS = "Bribed Captain", koKR = "매수된 대장", frFR = "Capitaine soudoyé", deDE = "Bestochener Hauptmann", zhCN = "受贿的队长", ptBR = "Capitão Subornado", esES = "Capitán sobornado", ruRU = "Подкупленный капитан", esMX = "Capitán sobornado", itIT = "Capitano Corrotto", zhTW = "受賄的隊長" },
    [253081] = { enUS = "Influentual Reviewer", koKR = "영향력 있는 평가자", frFR = "Influenceur critique", deDE = "Einflussreicher Rezensent", zhCN = "走红的评论家", ptBR = "Crítico Influente", esES = "Crítico influyente", ruRU = "Влиятельный критик", esMX = "", itIT = "Recensore Influente", zhTW = "重量級評論家" },
    [253324] = { enUS = "Tiny Felwyrm", koKR = "작은 지옥지룡", frFR = "Minuscule wyrm gangrené", deDE = "Winziger Teufelswyrm", zhCN = "小小邪能浮龙", ptBR = "Moreia Vil Pequenininha", esES = "Vermivil diminuto", ruRU = "Крошечный змей Скверны", esMX = "", itIT = "Piccolo Vildragone", zhTW = "小小魔化龍鰻" },
    [253571] = { enUS = "Bloodthorn Roots", koKR = "핏빛가시 뿌리", frFR = "Racines épine-sanglante", deDE = "Blutdornwurzeln", zhCN = "血棘之根", ptBR = "Raízes do Espinho Sangrento", esES = "Raíces sangrespina", ruRU = "Корни кровошипа", esMX = "", itIT = "Radici di Spinarossa", zhTW = "血棘之根" },
    [254677] = { enUS = "Ethereal Shade", koKR = "에테리얼 망령", frFR = "Ombre éthérienne", deDE = "Astraler Schemen", zhCN = "虚灵之影", ptBR = "Vulto Etéreo", esES = "Sombra etérea", ruRU = "Эфемерная тень", esMX = "", itIT = "Ombra Eterea", zhTW = "以太族之影" },
    [254850] = { enUS = "Sporeblight Belcher", koKR = "포자역병 트림꾼", frFR = "Cracheur sporefléau", deDE = "Sporenpestspucker", zhCN = "孢荒喷射者", ptBR = "Arrotão Praguesporo", esES = "Eructador esporizón", ruRU = "Спорогнилостный изрыгатель", esMX = "Eructador esporañublo", itIT = "Vomitatore Piagaspora", zhTW = "孢疫噴吐者" },
    [255000] = { enUS = "Targeting Stalker", koKR = "대상 지정 추적자", frFR = "Traqueur de ciblage", deDE = "Zielender Pirscher", zhCN = "指向追踪者", ptBR = "Espreitador de Seleção de Alvo", esES = "Acechador de objetivo", ruRU = "Преследователь цели", esMX = "", itIT = "Inseguitore del Bersaglio", zhTW = "鎖定目標的潛獵者" },
    [255001] = { enUS = "Gravitic Orb", koKR = "중력 보주", frFR = "Orbe gravitationnel", deDE = "Gravitationskugel", zhCN = "引力宝珠", ptBR = "Orbe Gravítico", esES = "Orbe gravitacional", ruRU = "Гравитационная сфера", esMX = "", itIT = "Globo Gravitazionale", zhTW = "重力球" },
    [255050] = { enUS = "Kystia Manaheart", koKR = "키스티아 마나하트", frFR = "Kystia Coeur-de-Mana", deDE = "Kystia Manaherz", zhCN = "凯斯媞亚·魔力之心", ptBR = "Kystia Manacárdia", esES = "Kystia Manaudaz", ruRU = "Кистия Сердце Маны", esMX = "", itIT = "Kystia Manacuore", zhTW = "克絲提雅‧法心" },
    [255604] = { enUS = "Seductive Sayaad", koKR = "고혹적인 세이야드", frFR = "Sayaad séducteur", deDE = "Verführerische Sayaad", zhCN = "诱惑的萨亚德", ptBR = "Sayaad Sedutor", esES = "Sayaad seductor", ruRU = "Сайаад-соблазнитель", esMX = "", itIT = "Sayaad Seduttivo", zhTW = "誘人的薩亞德" },
    [259445] = { enUS = "Rav'i", koKR = "라비", frFR = "Rav'i", deDE = "Rav'i", zhCN = "拉维", ptBR = "Rav'i", esES = "Rav'i", ruRU = "Рав'и", esMX = "", itIT = "Rav'i", zhTW = "瑞弗" },
    [259446] = { enUS = "The Writhing Coil", koKR = "격동하는 똬리", frFR = "L'Ophidien ondulant", deDE = "Das windende Knäuel", zhCN = "扭缠盘蛇", ptBR = "Espiral Contorcida", esES = "La Espiral Retorcida", ruRU = "Извивающийся виток", esMX = "", itIT = "Spirale Contorcente", zhTW = "扭動纏繞" },
    [259447] = { enUS = "Zul'jan", koKR = "줄잔", frFR = "Zul'jan", deDE = "Zul'jan", zhCN = "祖尔加", ptBR = "Zul'jan", esES = "Zul'jan", ruRU = "Зул'джан", esMX = "", itIT = "Zul'jan", zhTW = "祖爾詹" },
    [261550] = { enUS = "Venom Leech", koKR = "맹독 거머리", frFR = "Sangsue venimeuse", deDE = "Giftegel", zhCN = "毒液水蛭", ptBR = "Peçonhessuga", esES = "Parásito del veneno", ruRU = "Ядовитая пиявка", esMX = "Sanguijuela de veneno", itIT = "Sanguisuga Velenosa", zhTW = "劇毒水蛭" },
    [261552] = { enUS = "Bloodletter", koKR = "방혈뱀", frFR = "Saigneur", deDE = "Blutvergießer", zhCN = "放血者", ptBR = "Dessangrador", esES = "Flebotomista", ruRU = "Кровопускатель", esMX = "Flebotomista", itIT = "Spargisangue", zhTW = "放血者" },
    [261553] = { enUS = "Ravenous Descendant", koKR = "게걸스러운 후손", frFR = "Descendant vorace", deDE = "Gefräßiger Nachfahre", zhCN = "贪婪的后裔", ptBR = "Descendente Voraz", esES = "Descendiente voraz", ruRU = "Прожорливый потомок", esMX = "Descendiente voraz", itIT = "Discendente Famelico", zhTW = "飢餓的後裔" },
    [261554] = { enUS = "Twinfang Harrower", koKR = "쌍송곳니 박해자", frFR = "Persécuteur crochet-double", deDE = "Zwillingsfangplager", zhCN = "双牙蹂躏者", ptBR = "Consternador Presa Dupla", esES = "Lacerante de colmillos gemelos", ruRU = "Двуглавый кусатель", esMX = "Torturador doblecolmillo", itIT = "Straziatore dalle Zanne Gemelle", zhTW = "雙牙哈洛爾" },
    [261556] = { enUS = "Hatchling", koKR = "갓 태어난 뱀", frFR = "Jeune", deDE = "Jungtier", zhCN = "幼体", ptBR = "Filhote", esES = "Cría", ruRU = "Детеныш", esMX = "Cría", itIT = "Cucciolo", zhTW = "幼蛇" },
    [261557] = { enUS = "High Evolutionist", koKR = "고위 진화술사", frFR = "Grand évolutionniste", deDE = "Hochevolutionär", zhCN = "高阶进化者", ptBR = "Evolucionista Superior", esES = "Alto evolucionador", ruRU = "Верховный мастер эволюции", esMX = "Alto evolucionista", itIT = "Alto Evoluzionista", zhTW = "高等進化者" },
    [261560] = { enUS = "Primal Serpent", koKR = "원시의 독사", frFR = "Serpent primordial", deDE = "Urtümliche Schlange", zhCN = "原始毒蛇", ptBR = "Serpente Primeva", esES = "Sierpe primigenia", ruRU = "Изначальный змей", esMX = "Serpiente primigenia", itIT = "Serpente Primordiale", zhTW = "原始毒蛇" },
    [261573] = { enUS = "Ascendant Serpent", koKR = "승천한 뱀", frFR = "Serpent ascendant", deDE = "Aufsteigende Schlange", zhCN = "晋升之蛇", ptBR = "Serpente Ascendente", esES = "Sierpe ascendente", ruRU = "Вознесенный змей", esMX = "Serpiente ascendida", itIT = "Serpente Asceso", zhTW = "晉升毒蛇" },
    [262011] = { enUS = "Rattling Writhe", koKR = "덜거덕거리는 격동뱀", frFR = "Tortilleur cliquetant", deDE = "Klappernder Winder", zhCN = "振响的扭缠蛇", ptBR = "Contórcia Chacoalhante", esES = "Retuerto tintineante", ruRU = "Гремучий скользмей", esMX = "Contortio traqueteante", itIT = "Torsius Rantolante", zhTW = "顫響蛇妖" },
    [262398] = { enUS = "Uncoiled Writhe", koKR = "똬리 풀린 격동뱀", frFR = "Tortilleur déroulé", deDE = "Entschlungener Winder", zhCN = "溃散的扭缠蛇", ptBR = "Contórcia Desemaranhada", esES = "Retuerto involutado", ruRU = "Расплетенный скользмей", esMX = "", itIT = "Torsius Districati", zhTW = "解纏蛇妖" },
    [262530] = { enUS = "Adderis", koKR = "애더리스", frFR = "Viperis", deDE = "Adderis", zhCN = "阿德里斯", ptBR = "Vipperis", esES = "Adderis", ruRU = "Гюрзис", esMX = "", itIT = "Viperis", zhTW = "阿德利斯" },
    [262822] = { enUS = "Aspix", koKR = "아스픽스", frFR = "Aspis", deDE = "Aspix", zhCN = "阿斯匹克斯", ptBR = "Jararax", esES = "Aspix", ruRU = "Аспидис", esMX = "", itIT = "Aspix", zhTW = "艾斯匹" },
    [263109] = { enUS = "Ula'tek's Chosen", koKR = "울라텍의 간택자", frFR = "Elu d'Ula'tek", deDE = "Auserwählter von Ula'tek", zhCN = "乌拉特克神选者", ptBR = "Escolhido de Ula'tek", esES = "Elegido de Ula'tek", ruRU = "Избранник Ула'тек", esMX = "Elegido de Ula'tek", itIT = "Prescelto di Ula'tek", zhTW = "烏拉特克的選召者" },
    [263112] = { enUS = "Living Venom", koKR = "살아있는 맹독", frFR = "Venin vivant", deDE = "Lebendiges Gift", zhCN = "活体毒液", ptBR = "Peçonha Viva", esES = "Veneno viviente", ruRU = "Живой яд", esMX = "Veneno viviente", itIT = "Veleno Vivente", zhTW = "活體毒液" },
    [263181] = { enUS = "Egg", koKR = "알", frFR = "Oeuf", deDE = "Ei", zhCN = "卵的标记", ptBR = "Ovo", esES = "Huevo", ruRU = "Яйцо", esMX = "", itIT = "Uovo", zhTW = "蛋" },
    [263228] = { enUS = "Agitated Voidscythe", koKR = "동요한 공허낫", frFR = "Fauche-Vide agité", deDE = "Aufgebrachte Leerensense", zhCN = "焦躁的虚镰", ptBR = "Foice do Caos Agitada", esES = "Guadaña de Vacío perturbada", ruRU = "Взбудораженный серп Бездны", esMX = "Guadaña del Vacío agitada", itIT = "Falce del Vuoto Agitata", zhTW = "激動的虛無鐮刀" },
    [263383] = { enUS = "Snake", koKR = "뱀", frFR = "Serpent", deDE = "Schlange", zhCN = "蛇", ptBR = "Cobra", esES = "Serpiente", ruRU = "Змея", esMX = "", itIT = "Serpente", zhTW = "毒蛇" },
    [263658] = { enUS = "Galvazzt", koKR = "갈바즈트", frFR = "Galvazzt", deDE = "Galvazzt", zhCN = "加瓦兹特", ptBR = "Galvazzt", esES = "Galvazzt", ruRU = "Гальваззт", esMX = "", itIT = "Galvazzt", zhTW = "加瓦茲特" },
    [263940] = { enUS = "Belath Dawnblade", koKR = "벨라스 돈블레이드", frFR = "Belath Aubelame", deDE = "Belath Dämmerklinge", zhCN = "贝拉斯·黎明之刃", ptBR = "Belath Aurolume", esES = "Belath Hojalba", ruRU = "Белат Клинок Рассвета", esMX = "", itIT = "Belath Lamachiara", zhTW = "貝拉斯‧曦刃" },
    [264785] = { enUS = "Swarming Krolusk", koKR = "들끓는 크롤러스크", frFR = "Krolusk grouillant", deDE = "Schwärmender Krolusk", zhCN = "群聚三叶虫", ptBR = "Crocolusco Enxameante", esES = "Crolusco en enjambre", ruRU = "Стайный кролуск", esMX = "", itIT = "Krolusk Sciamante", zhTW = "群聚葉殼蟲" },
    [264798] = { enUS = "Infused Eggs", koKR = "주입된 알", frFR = "Oeufs imprégnés", deDE = "Erfüllte Eier", zhCN = "注能之卵", ptBR = "Ovos Imbuídos", esES = "Huevos imbuidos", ruRU = "Зараженные яйца", esMX = "", itIT = "Uova Infuse", zhTW = "灌能蛇蛋" },
    [265057] = { enUS = "Spark Channeler", koKR = "불꽃 역술사", frFR = "Canaliste d'étincelles", deDE = "Funkenkanalisierer", zhCN = "火花引导者", ptBR = "Canalizador de Centelhas Sombrio", esES = "Canalizador de chispas", ruRU = "Искротворец", esMX = "", itIT = "Canalizzatore di Scintille", zhTW = "火花傳導者" },
    [267545] = { enUS = "Aegyra the Unyielding", koKR = "불굴의 에이기라", frFR = "Aegyra l'Inflexible", deDE = "Aegyra die Unnachgiebige", zhCN = "不屈的埃吉拉", ptBR = "Aegyra, a Obstinada", esES = "Aegyra la Implacable", ruRU = "Эгира Непреклонная", esMX = "Aegyra, la Implacable", itIT = "Aegyra l'Implacabile", zhTW = "『不撓者』愛琪拉" },
    [267546] = { enUS = "Raj'kess the Spellstorm", koKR = "주문폭풍 라즈케스", frFR = "Raj'kess la Tempête ensorcelée", deDE = "Raj'kess der Zaubersturm", zhCN = "法术风暴拉杰克斯", ptBR = "Raj'kess, a Tempestade Mágica", esES = "Raj'kess la Geoarcana", ruRU = "Раж'кесс Чародейская буря", esMX = "Raj'kess, la Tormenta de Hechizos", itIT = "Raj'kess la Magitempesta", zhTW = "『法颶』拉捷克斯" },
    [268184] = { enUS = "Devouring Brutalizer", koKR = "포식하는 학대자", frFR = "Brutaliseur dévorant", deDE = "Verschlingender Metzler", zhCN = "贪噬残虐者", ptBR = "Brutalizador Devorador", esES = "Brutalizador de la Devoración", ruRU = "Всепожирающий изверг", esMX = "Brutalizador devorador", itIT = "Brutalizzatore Divorante", zhTW = "吞噬殘暴者" },
    [268317] = { enUS = "Faithless Tormentor", koKR = "부정한 고문관", frFR = "Tortionnaire infidèle", deDE = "Treuloser Peiniger", zhCN = "无信折磨者", ptBR = "Atormentador Ímpio", esES = "Atormentador infiel", ruRU = "Мучитель-отступник", esMX = "", itIT = "Tormentatore Senzafede", zhTW = "無信折磨者" },
    [268344] = { enUS = "Corrupted Guardian", koKR = "타락한 수호자", frFR = "Gardien corrompu", deDE = "Verderbter Wächter", zhCN = "堕落的守护者", ptBR = "Guardião Corrompido", esES = "Guardián corrupto", ruRU = "Зараженный порчей страж", esMX = "", itIT = "Guardiano Corrotto", zhTW = "腐化的守護者" },
    [268358] = { enUS = "Ritual Snake", koKR = "의식용 뱀", frFR = "Serpent rituel", deDE = "Ritualschlange", zhCN = "仪式毒蛇", ptBR = "Cobra Ritualística", esES = "Serpiente ritual", ruRU = "Ритуальный змей", esMX = "", itIT = "Serpente Rtuale", zhTW = "儀式毒蛇" },
    [268364] = { enUS = "Lifeforce", koKR = "생명력", frFR = "Force vitale", deDE = "Lebenskraft", zhCN = "生命之力", ptBR = "Força Vital", esES = "Fuerza vital", ruRU = "Жизненная сила", esMX = "", itIT = "Forza Vitale", zhTW = "生命力" },
    [268427] = { enUS = "Essence Defiler", koKR = "정수 모독자", frFR = "Souilleuse d'essence", deDE = "Essenzschänderin", zhCN = "精华污染者", ptBR = "Profanadora de Essência", esES = "Profanadora de esencia", ruRU = "Осквернительница сущности", esMX = "", itIT = "Profanatrice dell'Essenza", zhTW = "精華褻瀆者" },
    [268491] = { enUS = "Twisted Hexxer", koKR = "뒤틀린 사술사", frFR = "Maléficieur dénaturé", deDE = "Entstellter Hexer", zhCN = "扭曲的妖术师", ptBR = "Bagateiro Perverso", esES = "Aojador retorcido", ruRU = "Искаженный проклинатель", esMX = "", itIT = "Malefico Corrotto", zhTW = "扭曲妖術師" },
    [268729] = { enUS = "Faithless Tormentor", koKR = "부정한 고문관", frFR = "Tortionnaire infidèle", deDE = "Treuloser Peiniger", zhCN = "无信折磨者", ptBR = "Atormentador Ímpio", esES = "Atormentador infiel", ruRU = "Мучитель-отступник", esMX = "", itIT = "Tormentatore Senzafede", zhTW = "無信折磨者" },
    [268747] = { enUS = "Lesser Lifeforce", koKR = "하급 생명력", frFR = "Force vitale inférieure", deDE = "Geringere Lebenskraft", zhCN = "次级生命之力", ptBR = "Força Vital Inferior", esES = "Fuerza vital inferior", ruRU = "Малая жизненная сила", esMX = "", itIT = "Forza Vitale Minore", zhTW = "低階生命力" },
    [269227] = { enUS = "Temple Disruptor", koKR = "사원 분열자", frFR = "Disrupteur du temple", deDE = "Tempelstörer", zhCN = "神庙干扰者", ptBR = "Disruptor do Templo", esES = "Perturbador del templo", ruRU = "Храмовый дезинтегратор", esMX = "", itIT = "Disgregatore del Tempio", zhTW = "神殿干擾者" },
    [269808] = { enUS = "Aka'ali the Conqueror", koKR = "정복자 아카알리", frFR = "Aka'ali la Conquérante", deDE = "Aka'ali die Bezwingerin", zhCN = "征服者阿卡阿里", ptBR = "Aka'ali, a Conquistadora", esES = "Aka'ali la Conquistadora", ruRU = "Ака'али Завоевательница", esMX = "", itIT = "Aka'ali la Conquistatrice", zhTW = "『征服者』阿卡亞莉" },
    [269810] = { enUS = "Zanazal the Wise", koKR = "현자 자나잘", frFR = "Zanazal le Sage", deDE = "Zanazal der Weise", zhCN = "智者扎纳扎尔", ptBR = "Zanazal, o Sábio", esES = "Zanazal el Sabio", ruRU = "Заназал Мудрый", esMX = "", itIT = "Zanazal il Saggio", zhTW = "『智者』薩納瑟爾" },
    [269811] = { enUS = "Kula the Butcher", koKR = "도살자 쿨라", frFR = "Kula la Bouchère", deDE = "Kula die Schlächterin", zhCN = "屠夫库拉", ptBR = "Kula, a Açougueira", esES = "Kula la Carnicera", ruRU = "Кула Живодерка", esMX = "", itIT = "Kula la Macellaia", zhTW = "『屠殺者』庫拉" },
    [270306] = { enUS = "Ritual Chieftain", koKR = "의식의 족장", frFR = "Chef du rituel", deDE = "Ritualhäuptling", zhCN = "仪式首领", ptBR = "Chefe do Ritual", esES = "Jefe del ritual", ruRU = "Ритуальный вождь", esMX = "Jefe del ritual", itIT = "Capotribù Rituale", zhTW = "儀式酋長" },
    [270378] = { enUS = "Ritual Spirit", koKR = "의식 영혼", frFR = "Esprit rituel", deDE = "Ritualgeist", zhCN = "仪式精魂", ptBR = "Espírito Ritual", esES = "Espíritu de ritual", ruRU = "Ритуальный дух", esMX = "", itIT = "Spirito del Rituale", zhTW = "祭儀靈魂" },
    [270417] = { enUS = "Uncoiled Writhe", koKR = "똬리 풀린 격동뱀", frFR = "Tortilleur déroulé", deDE = "Entschlungener Winder", zhCN = "溃散的扭缠蛇", ptBR = "Contórcia Desemaranhada", esES = "Retuerto involutado", ruRU = "Расплетенный скользмей", esMX = "", itIT = "Torsius Districati", zhTW = "解纏蛇妖" },
    [270502] = { enUS = "Half-Finished Mummy", koKR = "반쯤 완성된 미라", frFR = "Momie à moitié terminée", deDE = "Halbfertige Mumie", zhCN = "未完成的木乃伊", ptBR = "Múmia Pela Metade", esES = "Momia a medio acabar", ruRU = "Недоделанная мумия", esMX = "", itIT = "Mummia Mezza Imbalsamata", zhTW = "半成品木乃伊" },
    [271453] = { enUS = "Blade of the Altar", koKR = "제단의 칼날", frFR = "Lame de l'autel", deDE = "Klinge des Altars", zhCN = "祭坛利刃", ptBR = "Lâmina do Altar", esES = "Hoja del altar", ruRU = "Алтарный клинок", esMX = "", itIT = "Lama dell'Altare", zhTW = "祭壇之刃" },
    [272074] = { enUS = "Volatile Totem", koKR = "불안정한 토템", frFR = "Totem instable", deDE = "Instabiles Totem", zhCN = "动荡图腾", ptBR = "Totem Volátil", esES = "Tótem volátil", ruRU = "Нестабильный тотем", esMX = "", itIT = "Totem Instabile", zhTW = "爆燃圖騰" },
    [272246] = { enUS = "Trained Felhunter", koKR = "조련된 지옥사냥개", frFR = "Chasseur corrompu dressé", deDE = "Ausgebildeter Teufelsjäger", zhCN = "驯服的地狱猎犬", ptBR = "Caçador Vil Treinado", esES = "Manáfago adiestrado", ruRU = "Дрессированный охотник Скверны", esMX = "", itIT = "Vilsegugio Addestrato", zhTW = "經過訓練的惡魔獵犬" },
    [273050] = { enUS = "Half-Finished Mummy", koKR = "반쯤 완성된 미라", frFR = "Momie à moitié terminée", deDE = "Halbfertige Mumie", zhCN = "未完成的木乃伊", ptBR = "Múmia Pela Metade", esES = "Momia a medio acabar", ruRU = "Недоделанная мумия", esMX = "", itIT = "Mummia Mezza Imbalsamata", zhTW = "半成品木乃伊" },
}
EXDB.NPCNameByID = EXDB.NPCNameSource
-- END GENERATED S2 NPC LOCALES

EXDB.InstanceNoteInstanceSource = {

    { mapID = 1762, instanceID = 1762, challengeModeID = 249, kind = "party", name = "诸王之眠", nameEN = "Kings' Rest", zhCNShort = "诸王", enUSShort = "KR", category = "other_1200" },
    { mapID = 1877, instanceID = 1877, challengeModeID = 250, kind = "party", name = "塞塔里斯神庙", nameEN = "Temple of Sethraliss", zhCNShort = "神庙", enUSShort = "ToS", category = "other_1200" },
    { mapID = 2521, instanceID = 2521, challengeModeID = 399, kind = "party", name = "红玉新生法池", nameEN = "Ruby Life Pools", zhCNShort = "红玉", enUSShort = "RLP", category = "other_1200" },
    { mapID = 2813, instanceID = 2813, challengeModeID = 587, kind = "party", name = "密谋小径", nameEN = "Murder Row", zhCNShort = "密谋", enUSShort = "MR", category = "other_1200" },
    { mapID = 2825, instanceID = 2825, challengeModeID = 586, kind = "party", name = "纳洛拉克的洞穴", nameEN = "Den of Nalorakk", zhCNShort = "洞穴", enUSShort = "DoN", category = "other_1200" },
    { mapID = 2859, instanceID = 2859, challengeModeID = 584, kind = "party", name = "夺目谷", nameEN = "The Blinding Vale", zhCNShort = "夺目", enUSShort = "BV", category = "other_1200" },
    { mapID = 2923, instanceID = 2923, challengeModeID = 585, kind = "party", name = "虚空之痕竞技场", nameEN = "Voidscar Arena", zhCNShort = "虚空", enUSShort = "VA", category = "other_1200" },
    { mapID = 2993, instanceID = 2993, challengeModeID = 588, kind = "party", name = "毒牙祭坛", nameEN = "Altar of Fangs", zhCNShort = "毒牙", enUSShort = "AoF", category = "other_1200" },
    { mapID = 1592, instanceID = 1592, kind = "raid", name = "孢陨幽境", nameEN = "Sporefall", category = "raid_s1" },
    { mapID = 3004, instanceID = 3004, kind = "raid", category = "raid_s2", name = "烈毒之渊", nameEN = "The Venomous Abyss" },
    { mapID = 2987, instanceID = 2987, kind = "raid", category = "raid_s2", name = "潮缚石窟", nameEN = "The Tidebound Grotto" },
}

-- BEGIN GENERATED S2 MAP LOCALES
EXDB.InstanceNoteS2MapLocaleSource = {
    [2813] = { enUS = "Murder Row", deDE = "Mördergasse", esES = "Frontal de la Muerte", esMX = "El Frontal de la Muerte", frFR = "Allée du meurtre", itIT = "Traversa degli Intrighi", koKR = "죽음의 골목", ptBR = "Travessa do Assassino", ruRU = "Закоулок душегубов", zhCN = "密谋小径", zhTW = "兇殺路" },
    [2859] = { enUS = "The Blinding Vale", deDE = "Das blendende Tal", esES = "Valle Cegador", esMX = "El Valle Enceguecedor", frFR = "Le val Aveuglant", itIT = "Valle Accecante", koKR = "눈부신 골짜기", ptBR = "O Vale Ofuscante", ruRU = "Слепящая долина", zhCN = "夺目谷", zhTW = "盲目谷地" },
    [2923] = { enUS = "Voidscar Arena", deDE = "Arena der Leerennarbe", esES = "Arena Lacravacua", esMX = "Arena Rajavacío", frFR = "Arène de la Cicatrice du Vide", itIT = "Arena Sfregiavuoto", koKR = "공허흉터 투기장", ptBR = "Arena da Chaga do Caos", ruRU = "Арена Шрама Бездны", zhCN = "虚空之痕竞技场", zhTW = "虛無之痕競技場" },
    [2825] = { enUS = "Den of Nalorakk", deDE = "Nalorakks Bau", esES = "Guarida de Nalorakk", esMX = "Guarida de Nalorakk", frFR = "Antre de Nalorakk", itIT = "Tana di Nalorakk", koKR = "날로라크의 소굴", ptBR = "Covil de Nalorakk", ruRU = "Берлога Налоракка", zhCN = "纳洛拉克的洞穴", zhTW = "納羅拉克之穴" },
    [2521] = { enUS = "Ruby Life Pools", deDE = "Rubinlebensbecken", esES = "Estanques de Vida Rubí", esMX = "Estanques de Vida Rubí", frFR = "Bassins de l’Essence rubis", itIT = "Pozze della Vita di Rubino", koKR = "루비 생명의 웅덩이", ptBR = "Poços da Vida Rubi", ruRU = "Рубиновые Омуты Жизни", zhCN = "红玉新生法池", zhTW = "晶紅生命之池" },
    [1762] = { enUS = "Kings' Rest", deDE = "Königsruh", esES = "Reposo de los Reyes", esMX = "Reposo de los Reyes", frFR = "Repos des rois", itIT = "Requie dei Re", koKR = "왕들의 안식처", ptBR = "Repouso do Rei", ruRU = "Гробница королей", zhCN = "诸王之眠", zhTW = "諸王之眠" },
    [1877] = { enUS = "Temple of Sethraliss", deDE = "Tempel von Sethraliss", esES = "Templo de Sethraliss", esMX = "Templo de Sethraliss", frFR = "Temple de Sephraliss", itIT = "Tempio di Sethraliss", koKR = "세스랄리스 사원", ptBR = "Templo de Sethraliss", ruRU = "Храм Сетралисс", zhCN = "塞塔里斯神庙", zhTW = "瑟沙利斯神廟" },
    [2993] = { enUS = "Altar of Fangs", deDE = "Altar der Fänge", esES = "Altar de los Colmillos", esMX = "Altar de Colmillos", frFR = "Autel des crochets", itIT = "Altare delle Zanne", koKR = "송곳니의 제단", ptBR = "Altar das Presas", ruRU = "Алтарь Клыков", zhCN = "毒牙祭坛", zhTW = "毒牙祭壇" },
    [3004] = { enUS = "The Venomous Abyss", deDE = "Der Giftige Abgrund", esES = "Abismo Venenoso", esMX = "El Abismo Venenoso", frFR = "L’abîme Venimeux", itIT = "Abissi Velenosi", koKR = "맹독 심연", ptBR = "Abismo Peçonhento", ruRU = "Отравленная бездна", zhCN = "烈毒之渊", zhTW = "劇毒深淵" },
    [2987] = { enUS = "The Tidebound Grotto", deDE = "Die Gezeitengebundene Grotte", esES = "Gruta Mareal", esMX = "La Gruta Mareal", frFR = "La grotte des Marées", itIT = "Grotta Vincolata alla Marea", koKR = "해일결속 동굴", ptBR = "Gruta Marejante", ruRU = "Приливный грот", zhCN = "潮缚石窟", zhTW = "浪縛岩窟" },
}
-- END GENERATED S2 MAP LOCALES





EXDB.InstanceNoteEncounterSource = {
    { encounterID = 3101, mapID = 2813, instanceID = 2813, name = "凯斯媞亚·魔力之心", nameEN = "Kystia Manaheart", enUS = "Kystia Manaheart", deDE = "Kystia Manaherz", esES = "Kystia Manaudaz", esMX = "Kystia Corazón de Maná", frFR = "Kystia Coeur-de-Mana", itIT = "Kystia Manacuore", koKR = "키스티아 마나하트", ptBR = "Kystia Manacárdia", ruRU = "Кистия Сердце Маны", zhCN = "凯斯媞亚·魔力之心", zhTW = "克絲提雅‧法心" },
    { encounterID = 3102, mapID = 2813, instanceID = 2813, name = "赞恩·刃悲", nameEN = "Zaen Bladesorrow", enUS = "Zaen Bladesorrow", deDE = "Zaen Klingentrauer", esES = "Zaen Hojapena", esMX = "Zaen Filopena", frFR = "Zaen Tristelame", itIT = "Zaen Dololama", koKR = "자엔 블레이드소로우", ptBR = "Zaen Laminúrio", ruRU = "Заэн Траурный Клинок", zhCN = "赞恩·刃悲", zhTW = "贊恩‧刃悲" },
    { encounterID = 3103, mapID = 2813, instanceID = 2813, name = "歼灭者萨祖克斯", nameEN = "Xathuux the Annihilator", enUS = "Xathuux the Annihilator", deDE = "Xathuux der Vernichter", esES = "Xathuux el Aniquilador", esMX = "Xathuux, el Aniquilador", frFR = "Xathuux l’Annihilateur", itIT = "Xathuux l'Annientatore", koKR = "파멸자 자투스", ptBR = "Xathuux, o Aniquilador", ruRU = "Затуукс Разрушитель", zhCN = "歼灭者萨祖克斯", zhTW = "『殲滅者』薩索克斯" },
    { encounterID = 3105, mapID = 2813, instanceID = 2813, name = "利希尔·烬怒", nameEN = "Lithiel Cinderfury", enUS = "Lithiel Cinderfury", deDE = "Lithiel Glutzorn", esES = "Lithiel Ciniracunda", esMX = "Lithiel Furicienta", frFR = "Lithiel Fureur-de-Cendre", itIT = "Lithiel Cenerfuria", koKR = "리시엘 신더퓨리", ptBR = "Lithiel Brasafúria", ruRU = "Литиэль Пепельная Ярость", zhCN = "利希尔·烬怒", zhTW = "莉希爾‧燼怒" },
    { encounterID = 3199, mapID = 2859, instanceID = 2859, name = "光明众花", nameEN = "Lightblossom Trinity", enUS = "Lightblossom Trinity", deDE = "Dreifaltigkeit der Lichtblume", esES = "Trinidad de floración de Luz", esMX = "Trinidad Broteluz", frFR = "Trinité du lumiflore", itIT = "Trinità Fiordiluce", koKR = "빛송이 삼위일체", ptBR = "Trindade Botão de Luz", ruRU = "Светоцветное трио", zhCN = "光明众花", zhTW = "光綻三人組" },
    { encounterID = 3200, mapID = 2859, instanceID = 2859, name = "圣光猎手伊库兹", nameEN = "Ikuzz the Light Hunter", enUS = "Ikuzz the Light Hunter", deDE = "Ikuzz der Lichtjäger", esES = "Ikuzz el cazador de Luz", esMX = "Ikuzz, el cazador de luz", frFR = "Chasselumière Ikuzz", itIT = "Ikuzz il Cacciatore di Luce", koKR = "빛 사냥꾼 이쿠즈", ptBR = "Ikanz, o Caça-luz", ruRU = "Икузз Охотник Света", zhCN = "圣光猎手伊库兹", zhTW = "『聖光獵人』伊庫茲" },
    { encounterID = 3201, mapID = 2859, instanceID = 2859, name = "护光者鲁伊亚", nameEN = "Lightwarden Ruia", enUS = "Lightwarden Ruia", deDE = "Lichthüter Ruia", esES = "Celador de la Luz Ruia", esMX = "Celador de la luz Ruia", frFR = "Gardelumière Ruia", itIT = "Custode della Luce Ruia", koKR = "빛의 감시자 루이아", ptBR = "Guardião da Luz Ruia", ruRU = "Страж Света Руйя", zhCN = "护光者鲁伊亚", zhTW = "護光者魯亞" },
    { encounterID = 3202, mapID = 2859, instanceID = 2859, name = "兹欧凯特", nameEN = "Ziekett", enUS = "Ziekett", deDE = "Ziekett", esES = "Ziekett", esMX = "Ziekett", frFR = "Ziekett", itIT = "Ziekett", koKR = "지케트", ptBR = "Ziekett", ruRU = "Зиекетт", zhCN = "兹欧凯特", zhTW = "齊克特" },
    { encounterID = 3285, mapID = 2923, instanceID = 2923, name = "塔兹拉尔", nameEN = "Taz'Rah", enUS = "Taz'Rah", deDE = "Taz'Rah", esES = "Taz'Rah", esMX = "Taz'Rah", frFR = "Taz’Rah", itIT = "Taz'rah", koKR = "타즈라", ptBR = "Taz'Rah", ruRU = "Таз'ра", zhCN = "塔兹拉尔", zhTW = "塔茲拉" },
    { encounterID = 3286, mapID = 2923, instanceID = 2923, name = "阿特洛苏斯", nameEN = "Atroxus", enUS = "Atroxus", deDE = "Atroxus", esES = "Atroxus", esMX = "Atroxus", frFR = "Atroxus", itIT = "Atroxus", koKR = "아트로서스", ptBR = "Atroxus", ruRU = "Атрокс", zhCN = "阿特洛苏斯", zhTW = "奧托薩斯" },
    { encounterID = 3287, mapID = 2923, instanceID = 2923, name = "煞戎努斯", nameEN = "Charonus", enUS = "Charonus", deDE = "Charonus", esES = "Caronus", esMX = "Carbonus", frFR = "Charonus", itIT = "Charonus", koKR = "차로누스", ptBR = "Charonus", ruRU = "Харон", zhCN = "煞戎努斯", zhTW = "查洛納斯" },
    { encounterID = 3207, mapID = 2825, instanceID = 2825, name = "囤宝狂人", nameEN = "The Hoardmonger", enUS = "The Hoardmonger", deDE = "Der Hortraffer", esES = "El Acaparatesoros", esMX = "El Acaparador de Tesoros", frFR = "Le Thésauriseur", itIT = "L'Accumulatore", koKR = "비축광", ptBR = "O Acumulista", ruRU = "Прозапасник", zhCN = "囤宝狂人", zhTW = "囤積者" },
    { encounterID = 3208, mapID = 2825, instanceID = 2825, name = "寒冬哨兵", nameEN = "Sentinel of Winter", enUS = "Sentinel of Winter", deDE = "Winterwache", esES = "Centinela del invierno", esMX = "Centinela del invierno", frFR = "Sentinelle de l’hiver", itIT = "Sentinella dell'Inverno", koKR = "겨울의 파수꾼", ptBR = "Sentinela do Inverno", ruRU = "Часовой зимы", zhCN = "寒冬哨兵", zhTW = "凜冬哨兵" },
    { encounterID = 3209, mapID = 2825, instanceID = 2825, name = "纳洛拉克", nameEN = "Nalorakk", enUS = "Nalorakk", deDE = "Nalorakk", esES = "Nalorakk", esMX = "Nalorakk", frFR = "Nalorakk", itIT = "Nalorakk", koKR = "날로라크", ptBR = "Nalorakk", ruRU = "Налоракк", zhCN = "纳洛拉克", zhTW = "納羅拉克" },
    { encounterID = 2609, mapID = 2521, instanceID = 2521, name = "梅莉杜莎·寒妆", nameEN = "Melidrussa Chillworn", enUS = "Melidrussa Chillworn", deDE = "Melidrussa die Unterkühlte", esES = "Melidrussa Ajafrío", esMX = "Melidrussa Tejescarcha", frFR = "Mélidrussa Manteglace", itIT = "Melidrussa Gelolacero", koKR = "멜리드루사 칠원", ptBR = "Melidrussa Geladura", ruRU = "Мелидрусса Истощенная Холодом", zhCN = "梅莉杜莎·寒妆", zhTW = "梅莉卓沙‧寒磨" },
    { encounterID = 2606, mapID = 2521, instanceID = 2521, name = "柯姬雅·焰蹄", nameEN = "Kokia Blazehoof", enUS = "Kokia Blazehoof", deDE = "Kokia Feuerhuf", esES = "Kokia Pezuña de Fuego", esMX = "Kokia Pezuña Ardiente", frFR = "Kokia Foulebraise", itIT = "Kokia Zoccolo Ardente", koKR = "코키아 블레이즈후프", ptBR = "Kokia Patardida", ruRU = "Кокия Пламенное Копыто", zhCN = "柯姬雅·焰蹄", zhTW = "可幾亞‧焰蹄" },
    { encounterID = 2623, mapID = 2521, instanceID = 2521, name = "基拉卡与厄克哈特·风脉", nameEN = "Kyrakka and Erkhart Stormvein", enUS = "Kyrakka and Erkhart Stormvein", deDE = "Kyrakka und Erkhart Sturmader", esES = "Kyrakka y Erkhart Venatormenta", esMX = "Kyrakka y Erkhart Sangre Tormentosa", frFR = "Kyrakka et Erkhart Foudreveine", itIT = "Kyrakka ed Erkhart Venariosa", koKR = "카이락카와 에크하트 스톰베인", ptBR = "Kyrakka e Erkhart Vendaveia", ruRU = "Киракка и Эркхарт Кровь Бури", zhCN = "基拉卡与厄克哈特·风脉", zhTW = "凱拉卡及俄克哈‧風脈" },
    { encounterID = 2139, mapID = 1762, instanceID = 1762, name = "黄金风蛇", nameEN = "The Golden Serpent", enUS = "The Golden Serpent", deDE = "Die Goldschlange", esES = "Serpiente dorada", esMX = "La serpiente dorada", frFR = "Le serpent doré", itIT = "Serpente Dorato", koKR = "황금 날뱀", ptBR = "A Serpente Dourada", ruRU = "Золотой Змей", zhCN = "黄金风蛇", zhTW = "黃金風蛇" },
    { encounterID = 2142, mapID = 1762, instanceID = 1762, name = "殓尸者姆沁巴", nameEN = "Mchimba the Embalmer", enUS = "Mchimba the Embalmer", deDE = "Mchimba der Balsamierer", esES = "Mchimba el Embalsamador", esMX = "Mchimba el Embalsamador", frFR = "Mchimba l’Embaumeur", itIT = "Mchimba l'Imbalsamatore", koKR = "장의사 음침바", ptBR = "Muquimba, o Embalsamador", ruRU = "Мчимба Бальзамировщик", zhCN = "殓尸者姆沁巴", zhTW = "『墓葬者』瑪欽巴" },
    { encounterID = 2140, mapID = 1762, instanceID = 1762, name = "部族议会", nameEN = "The Council of Tribes", enUS = "The Council of Tribes", deDE = "Der Rat der Stämme", esES = "El Consejo de las Tribus", esMX = "El Consejo de las tribus", frFR = "Le conseil des tribus", itIT = "Concilio delle Tribù", koKR = "부족 의회", ptBR = "O Conselho das Tribos", ruRU = "Совет племен", zhCN = "部族议会", zhTW = "部族議會" },
    { encounterID = 2143, mapID = 1762, instanceID = 1762, name = "达萨大王", nameEN = "King Dazar", enUS = "King Dazar", deDE = "König Dazar", esES = "Rey Dazar", esMX = "Rey Dazar", frFR = "Roi Dazar", itIT = "Re Dazar", koKR = "왕 다자르", ptBR = "Rei Dazar", ruRU = "Король Дазар", zhCN = "达萨大王", zhTW = "神王達薩" },
    { encounterID = 2124, mapID = 1877, instanceID = 1877, name = "阿德里斯和阿斯匹克斯", nameEN = "Adderis and Aspix", enUS = "Adderis and Aspix", deDE = "Adderis und Aspix", esES = "Adderis y Aspix", esMX = "Culebris y Aspix", frFR = "Viperis et Aspis", itIT = "Viperis e Aspix", koKR = "애더리스와 아스픽스", ptBR = "Vipperis e Jararax", ruRU = "Гюрзис и Аспидис", zhCN = "阿德里斯和阿斯匹克斯", zhTW = "阿德利斯和艾斯匹" },
    { encounterID = 2125, mapID = 1877, instanceID = 1877, name = "米利克萨", nameEN = "Merektha", enUS = "Merektha", deDE = "Merektha", esES = "Merektha", esMX = "Merektha", frFR = "Merekpha", itIT = "Merektha", koKR = "메레크타", ptBR = "Merektha", ruRU = "Меректа", zhCN = "米利克萨", zhTW = "莫芮克莎" },
    { encounterID = 2126, mapID = 1877, instanceID = 1877, name = "加瓦兹特", nameEN = "Galvazzt", enUS = "Galvazzt", deDE = "Galvazzt", esES = "Galvazzt", esMX = "Galvazzt", frFR = "Galvazzt", itIT = "Galvazzt", koKR = "갈바즈트", ptBR = "Galvazzt", ruRU = "Гальваззт", zhCN = "加瓦兹特", zhTW = "加瓦茲特" },
    { encounterID = 2127, mapID = 1877, instanceID = 1877, name = "塞塔里斯的化身", nameEN = "Avatar of Sethraliss", enUS = "Avatar of Sethraliss", deDE = "Avatar von Sethraliss", esES = "Avatar de Sethraliss", esMX = "Avatar de Sethraliss", frFR = "Avatar de Sephraliss", itIT = "Avatar di Sethraliss", koKR = "세스랄리스의 화신", ptBR = "Avatar de Sethraliss", ruRU = "Аватара Сетралисс", zhCN = "塞塔里斯的化身", zhTW = "瑟沙利斯化身" },
    { encounterID = 3456, mapID = 2993, instanceID = 2993, name = "拉维", nameEN = "Rav'i", enUS = "Rav'i", deDE = "Rav'i", esES = "Rav'i", esMX = "Rav'i", frFR = "Rav’i", itIT = "Rav'i", koKR = "라비", ptBR = "Rav'i", ruRU = "Рав'и", zhCN = "拉维", zhTW = "瑞弗" },
    { encounterID = 3457, mapID = 2993, instanceID = 2993, name = "扭缠盘蛇", nameEN = "The Writhing Coil", enUS = "The Writhing Coil", deDE = "Das windende Knäuel", esES = "La Espiral Retorcida", esMX = "El Retorcimiento en vida", frFR = "L’Ophidien ondulant", itIT = "Spirale Contorcente", koKR = "격동하는 똬리", ptBR = "Espiral Contorcida", ruRU = "Извивающийся виток", zhCN = "扭缠盘蛇", zhTW = "糾纏蛇妖" },
    { encounterID = 3458, mapID = 2993, instanceID = 2993, name = "祖尔加", nameEN = "Zul'jan", enUS = "Zul'jan", deDE = "Zul'jan", esES = "Zul'jan", esMX = "Zul'jan", frFR = "Zul’jan", itIT = "Zul'jan", koKR = "줄잔", ptBR = "Zul'jan", ruRU = "Зул'джан", zhCN = "祖尔加", zhTW = "祖爾詹" },
    { encounterID = 3470, mapID = 3004, instanceID = 3004, name = "盘魂者内克扎莉", nameEN = "Nek'zali the Soulcoiler", enUS = "Nek'zali the Soulcoiler", deDE = "Nek'zali die Seelenwinderin", esES = "Nek'zali la Volutadora de Almas", esMX = "Nek'zali, la Enrollaalmas", frFR = "Nek’zali l’Entortillâme", itIT = "Nek'zali la Spiranima", koKR = "영혼살무사 네크잘리", ptBR = "Nek'zali, a Enrosca-almas", ruRU = "Нек'зали Душительница Душ", zhCN = "盘魂者内克扎莉", zhTW = "『纏魂者』尼札利" },
    { encounterID = 3445, mapID = 3004, instanceID = 3004, name = "陵寝哨兵", nameEN = "Entombed Sentinels", enUS = "Entombed Sentinels", deDE = "Eingeschlossene Wächter", esES = "Centinelas Sepultados", esMX = "Centinelas Sepultados", frFR = "Sentinelles inhumées", itIT = "Sentinelle Sepolte", koKR = "매장된 파수꾼", ptBR = "Sentinelas Sepultadas", ruRU = "Погребенные стражи", zhCN = "陵寝哨兵", zhTW = "埋葬衛哨" },
    { encounterID = 3497, mapID = 3004, instanceID = 3004, name = "迷失的探险者", nameEN = "The Lost Explorers", enUS = "The Lost Explorers", deDE = "Die verirrten Entdecker", esES = "Los exploradores perdidos", esMX = "Los expedicionarios perdidos", frFR = "L’expédition perdue", itIT = "Gli Esploratori Perduti", koKR = "길 잃은 탐험가", ptBR = "Exploradores Perdidos", ruRU = "Потерявшиеся исследователи", zhCN = "迷失的探险者", zhTW = "迷路的探險者" },
    { encounterID = 3455, mapID = 3004, instanceID = 3004, name = "万毒邪祟者瓦什尼克", nameEN = "Vashnik the Malignant", enUS = "Vashnik the Malignant", deDE = "Vashnik der Bösartige", esES = "Vashnik el Maligno", esMX = "Vashnik, el Maligno", frFR = "Vashnik le Malveillant", itIT = "Vashnik il Maligno", koKR = "악성의 바쉬니크", ptBR = "Vashnik, o Maligno", ruRU = "Вашник Тлетворный", zhCN = "万毒邪祟者瓦什尼克", zhTW = "『惡性之毒』伐許尼克" },
    { encounterID = 3420, mapID = 3004, instanceID = 3004, name = "斯索拉克", nameEN = "Sszorak", enUS = "Sszorak", deDE = "Sszorak", esES = "Sszorak", esMX = "Sszorak", frFR = "Sszorak", itIT = "Sszorak", koKR = "스조라크", ptBR = "Sszorak", ruRU = "Ссзорак", zhCN = "斯索拉克", zhTW = "司佐拉" },
    { encounterID = 3421, mapID = 3004, instanceID = 3004, name = "双子毒牙", nameEN = "The Twin Fangs", enUS = "The Twin Fangs", deDE = "Die Zwillingsfänge", esES = "Los colmillos gemelos", esMX = "Los Colmillos Gemelos", frFR = "Les crochets jumeaux", itIT = "Zanne Gemelle", koKR = "쌍둥이 송곳니", ptBR = "As Presas Gêmeas", ruRU = "Два Клыка", zhCN = "双子毒牙", zhTW = "雙生毒牙" },
    { encounterID = 3429, mapID = 3004, instanceID = 3004, name = "盘卷祭坛", nameEN = "The Coiled Altar", enUS = "The Coiled Altar", deDE = "Der Gewundene Altar", esES = "El Altar en Espiral", esMX = "El Altar Serpenteante", frFR = "Autel Annelé", itIT = "Altare Serpeggiante", koKR = "똬리의 제단", ptBR = "O Altar Enrolado", ruRU = "Спиральный алтарь", zhCN = "盘卷祭坛", zhTW = "盤蛇祭壇" },
    { encounterID = 3492, mapID = 3004, instanceID = 3004, name = "乌拉特克", nameEN = "Ula'tek", enUS = "Ula'tek", deDE = "Ula'tek", esES = "Ula'tek", esMX = "Ula'tek", frFR = "Ula’tek", itIT = "Ula'tek", koKR = "울라텍", ptBR = "Ula'tek", ruRU = "Ула'тек", zhCN = "乌拉特克", zhTW = "烏拉特克" },
    { encounterID = 3379, mapID = 2987, instanceID = 2987, name = "尼姆瑞莎·唤波者", nameEN = "Nymrissa Wavecaller", enUS = "Nymrissa Wavecaller", deDE = "Nymrissa Wellenrufer", esES = "Nymrissa Clamaolas", esMX = "Nymrissa Clamaolas", frFR = "Nymrissa Mande-vagues", itIT = "Invocatrice dell'Onda Nymrissa", koKR = "님리사 웨이브콜러", ptBR = "Nymrissa Clamaondas", ruRU = "Нимрисса Волногон", zhCN = "尼姆瑞莎·唤波者", zhTW = "妮莉莎‧喚浪者" },
    { encounterID = 2065, mapID = 1753, instanceID = 1753, name = "晋升者祖拉尔", nameEN = "Zuraal the Ascended", enUS = "Zuraal the Ascended", deDE = "Zuraal der Aufgestiegene", esES = "Zuraal el Ascendido", esMX = "Zuraal, el Ascendido", frFR = "Zuraal le Zélateur", itIT = "Zuraal l'Asceso", koKR = "승천자 주라알", ptBR = "Zuraal, o Elevado", ruRU = "Зураал Перерожденный", zhCN = "晋升者祖拉尔", zhTW = "『超凡者』祖拉爾" },
    { encounterID = 2066, mapID = 1753, instanceID = 1753, name = "萨普瑞什", nameEN = "Saprish", enUS = "Saprish", deDE = "Saprish", esES = "Saprish", esMX = "Saprish", frFR = "Saprish", itIT = "Saprish", koKR = "사프리쉬", ptBR = "Saprish", ruRU = "Сарпиш", zhCN = "萨普瑞什", zhTW = "賽普瑞許" },
    { encounterID = 2067, mapID = 1753, instanceID = 1753, name = "总督奈扎尔", nameEN = "Viceroy Nezhar", enUS = "Viceroy Nezhar", deDE = "Vizekönig Nezhar", esES = "Virrey Nezhar", esMX = "Virrey Nezhar", frFR = "Vice-roi Nezhar", itIT = "Viceré Nezhar", koKR = "총독 네자르", ptBR = "Vice-rei Nezhar", ruRU = "Наместник Незжар", zhCN = "总督奈扎尔", zhTW = "副將聶薩" },
    { encounterID = 2068, mapID = 1753, instanceID = 1753, name = "鲁拉", nameEN = "L'ura", enUS = "L'ura", deDE = "L'ura", esES = "L'ura", esMX = "L'ura", frFR = "L’ura", itIT = "L'ura", koKR = "르우라", ptBR = "L'ura", ruRU = "Л'ура", zhCN = "鲁拉", zhTW = "路拉" },
    { encounterID = 1999, mapID = 658, instanceID = 658, name = "熔炉之主加弗斯特", nameEN = "Forgemaster Garfrost", enUS = "Forgemaster Garfrost", deDE = "Schmiedemeister Garfrost", esES = "Maestro de forja Gargelus", esMX = "Maestro de forja Gargelus", frFR = "Maître-forge Gargivre", itIT = "Mastro Forgiatore Gargelo", koKR = "제련장인 가프로스트", ptBR = "Mestre Forjador Criomal", ruRU = "Начальник кузни Гархлад", zhCN = "熔炉之主加弗斯特", zhTW = "鍛造大師加弗羅斯" },
    { encounterID = 2001, mapID = 658, instanceID = 658, name = "伊克和科瑞克", nameEN = "Ick and Krick", enUS = "Ick and Krick", deDE = "Ick und Krick", esES = "Agh y Puagh", esMX = "Agh y Puagh", frFR = "Ick et Krick", itIT = "Ick e Krick", koKR = "이크와 크리크", ptBR = "Ick e Krick", ruRU = "Ик и Крик", zhCN = "伊克和科瑞克", zhTW = "艾克與克瑞克" },
    { encounterID = 2000, mapID = 658, instanceID = 658, name = "天灾领主泰兰努斯", nameEN = "Scourgelord Tyrannus", enUS = "Scourgelord Tyrannus", deDE = "Geißelfürst Tyrannus", esES = "Señor de la Plaga Tyrannus", esMX = "Señor de la Plaga Tyrannus", frFR = "Seigneur du Fléau Tyrannus", itIT = "Signore della Piaga Tirannus", koKR = "스컬지군주 티라누스", ptBR = "Senhor do Flagelo Tyrannus", ruRU = "Повелитель Плети Тираний", zhCN = "天灾领主泰兰努斯", zhTW = "天譴領主提朗紐斯" },
    { encounterID = 1698, mapID = 1209, instanceID = 1209, name = "兰吉特", nameEN = "Ranjit", enUS = "Ranjit", deDE = "Ranjit", esES = "Ranjit", esMX = "Ranjit", frFR = "Ranjit", itIT = "Ranjit", koKR = "란지트", ptBR = "Ranjit", ruRU = "Ранжит", zhCN = "兰吉特", zhTW = "蘭吉特" },
    { encounterID = 1699, mapID = 1209, instanceID = 1209, name = "阿拉卡纳斯", nameEN = "Araknath", enUS = "Araknath", deDE = "Araknath", esES = "Araknath", esMX = "Araknath", frFR = "Araknath", itIT = "Araknath", koKR = "아라크나스", ptBR = "Araknath", ruRU = "Аракнат", zhCN = "阿拉卡纳斯", zhTW = "阿拉卡納斯" },
    { encounterID = 1700, mapID = 1209, instanceID = 1209, name = "鲁克兰", nameEN = "Rukhran", enUS = "Rukhran", deDE = "Rukhran", esES = "Rukhran", esMX = "Rukhran", frFR = "Rukhran", itIT = "Rukhran", koKR = "루크란", ptBR = "Rukhran", ruRU = "Рухран", zhCN = "鲁克兰", zhTW = "盧克然" },
    { encounterID = 1701, mapID = 1209, instanceID = 1209, name = "高阶贤者维里克斯", nameEN = "High Sage Viryx", enUS = "High Sage Viryx", deDE = "Oberste Weise Viryx", esES = "Suma sabia Viryx", esMX = "Gran Sabia Viryx", frFR = "Grand sage Viryx", itIT = "Alta Saggia Viryx", koKR = "대현자 비릭스", ptBR = "Alta Sábia Viryx", ruRU = "Высший мудрец Вирикс", zhCN = "高阶贤者维里克斯", zhTW = "大賢者維瑞思" },
    { encounterID = 2562, mapID = 2526, instanceID = 2526, name = "维克萨姆斯", nameEN = "Vexamus", enUS = "Vexamus", deDE = "Vexamus", esES = "Vexamus", esMX = "Vexamus", frFR = "Vexamus", itIT = "Vexamus", koKR = "벡사무스", ptBR = "Vexamus", ruRU = "Вексам", zhCN = "维克萨姆斯", zhTW = "維薩穆斯" },
    { encounterID = 2563, mapID = 2526, instanceID = 2526, name = "茂林古树", nameEN = "Overgrown Ancient", enUS = "Overgrown Ancient", deDE = "Überwuchertes Urtum", esES = "Anciano desmesurado", esMX = "Anciano sin podar", frFR = "Ancien embroussaillé", itIT = "Antico Erboso", koKR = "비대해진 고대정령", ptBR = "Anciente Supercrescido", ruRU = "Заросшее древо", zhCN = "茂林古树", zhTW = "生長過盛的古樹" },
    { encounterID = 2564, mapID = 2526, instanceID = 2526, name = "克罗兹", nameEN = "Crawth", enUS = "Crawth", deDE = "Kraas", esES = "Crawth", esMX = "Graznat", frFR = "Tricérabec", itIT = "Crawth", koKR = "크로스", ptBR = "Crawth", ruRU = "Кроут", zhCN = "克罗兹", zhTW = "克若絲" },
    { encounterID = 2565, mapID = 2526, instanceID = 2526, name = "多拉苟萨的回响", nameEN = "Echo of Doragosa", enUS = "Echo of Doragosa", deDE = "Echo von Doragosa", esES = "Eco de Doragosa", esMX = "Eco de Doragosa", frFR = "Écho de Doragosa", itIT = "Eco di Doragosa", koKR = "도라고사의 메아리", ptBR = "Eco de Doragosa", ruRU = "Эхо Дорагосы", zhCN = "多拉苟萨的回响", zhTW = "朵拉苟莎的回音" },
    { encounterID = 3056, mapID = 2805, instanceID = 2805, name = "烬晓", nameEN = "Emberdawn", enUS = "Emberdawn", deDE = "Dämmerglut", esES = "Brasalbor", esMX = "Brasalba", frFR = "Aube-de-Braise", itIT = "Albardente", koKR = "잿불여명", ptBR = "Brasaurora", ruRU = "Алозар", zhCN = "烬晓", zhTW = "燼晨" },
    { encounterID = 3057, mapID = 2805, instanceID = 2805, name = "被遗弃的二人组", nameEN = "Derelict Duo", enUS = "Derelict Duo", deDE = "Heruntergekommenes Duo", esES = "Dúo derelicto", esMX = "Dúo olvidado", frFR = "Duo abandonné", itIT = "Coppia di Derelitti", koKR = "버려진 2인조", ptBR = "Duo Arruinado", ruRU = "Дряхлый дуэт", zhCN = "被遗弃的二人组", zhTW = "被遺棄的雙人組" },
    { encounterID = 3058, mapID = 2805, instanceID = 2805, name = "指挥官克罗鲁科", nameEN = "Commander Kroluk", enUS = "Commander Kroluk", deDE = "Kommandant Kroluk", esES = "Comandante Kroluk", esMX = "Comandante Kroluk", frFR = "Commandant Kroluk", itIT = "Comandante Kroluk", koKR = "지휘관 크롤루크", ptBR = "Comandante Kroluk", ruRU = "Командир Кролук", zhCN = "指挥官克罗鲁科", zhTW = "指揮官寇魯克" },
    { encounterID = 3059, mapID = 2805, instanceID = 2805, name = "无眠之心", nameEN = "Restless Heart", enUS = "Restless Heart", deDE = "Rastloses Herz", esES = "Corazón Inquieto", esMX = "Corazón inquieto", frFR = "Cœur fébrile", itIT = "Cuore Irrequieto", koKR = "잠 못 드는 심장", ptBR = "Coração Inquieto", ruRU = "Неупокоенное сердце", zhCN = "无眠之心", zhTW = "躁動之心" },
    { encounterID = 3071, mapID = 2811, instanceID = 2811, name = "奥能金刚库斯托斯", nameEN = "Arcanotron Custos", enUS = "Arcanotron Custos", deDE = "Arkanotronwächter", esES = "Arcanotron Custos", esMX = "Arcanotrón Custos", frFR = "Assemblage arcanique de dispersion des foules", itIT = "Arcanotron Custos", koKR = "비전골렘 쿠스토스", ptBR = "Arcanotron Custoz", ruRU = "Чаротрон Кустос", zhCN = "奥能金刚库斯托斯", zhTW = "秘法號卡司托斯" },
    { encounterID = 3072, mapID = 2811, instanceID = 2811, name = "瑟拉奈尔·日鞭", nameEN = "Seranel Sunlash", enUS = "Seranel Sunlash", deDE = "Seranel Sonnenpeitsche", esES = "Seranel Cortasol", esMX = "Seranel Tajosol", frFR = "Séranel Cinglesoleil", itIT = "Seranel Frustasole", koKR = "사라넬 선래쉬", ptBR = "Seranel Talho do Sol", ruRU = "Серанель Бич Солнца", zhCN = "瑟拉奈尔·日鞭", zhTW = "薩拉奈爾‧日笞" },
    { encounterID = 3073, mapID = 2811, instanceID = 2811, name = "吉美尔鲁斯", nameEN = "Gemellus", enUS = "Gemellus", deDE = "Gemellus", esES = "Gemellus", esMX = "Gemellus", frFR = "Gémellus", itIT = "Gemellus", koKR = "제멜루스", ptBR = "Gemellus", ruRU = "Гемелл", zhCN = "吉美尔鲁斯", zhTW = "傑莫勒斯" },
    { encounterID = 3074, mapID = 2811, instanceID = 2811, name = "迪詹崔乌斯", nameEN = "Degentrius", enUS = "Degentrius", deDE = "Degentrius", esES = "Degentrius", esMX = "Degentrius", frFR = "Dégentrius", itIT = "Degentrius", koKR = "디젠트리우스", ptBR = "Degentrius", ruRU = "Дегентрий", zhCN = "迪詹崔乌斯", zhTW = "迪杰崔斯" },
    { encounterID = 3212, mapID = 2874, instanceID = 2874, name = "姆罗金和内克拉克斯", nameEN = "Muro'jin and Nekraxx", enUS = "Muro'jin and Nekraxx", deDE = "Muro'jin und Nekraxx", esES = "Muro'jin y Nekraxx", esMX = "Muro'jin y Nekraxx", frFR = "Muro’jin et Nekraxx", itIT = "Muro'jin e Nekraxx", koKR = "무로진과 네크락스", ptBR = "Muro'jin e Nekraxx", ruRU = "Муро'джин и Некракс", zhCN = "姆罗金和内克拉克斯", zhTW = "穆羅金與奈卡雷斯" },
    { encounterID = 3213, mapID = 2874, instanceID = 2874, name = "沃达扎", nameEN = "Vordaza", enUS = "Vordaza", deDE = "Vordaza", esES = "Vordaza", esMX = "Vordaza", frFR = "Vordaza", itIT = "Vordaza", koKR = "보르다자", ptBR = "Vordaza", ruRU = "Вордаза", zhCN = "沃达扎", zhTW = "沃達莎" },
    { encounterID = 3214, mapID = 2874, instanceID = 2874, name = "拉克图尔，聚魂之器", nameEN = "Rak'tul, Vessel of Souls", enUS = "Rak'tul, Vessel of Souls", deDE = "Rak'tul, Gefäß der Seelen", esES = "Rak'tul, receptáculo de almas", esMX = "Rak'tul, Receptáculo de almas", frFR = "Rak’tul, réceptacle des âmes", itIT = "Rak'tul, Ricettacolo d'Anime", koKR = "영혼의 그릇 락툴", ptBR = "Rak'tul, Receptáculo das Almas", ruRU = "Рак'тул Сосуд Душ", zhCN = "拉克图尔，聚魂之器", zhTW = "『靈魂容器』拉克圖" },
    { encounterID = 3328, mapID = 2915, instanceID = 2915, name = "核技工程长卡斯雷瑟", nameEN = "Chief Corewright Kasreth", enUS = "Chief Corewright Kasreth", deDE = "Oberster Kernbauer Kasreth", esES = "Jefe nucleoartesano Kasreth", esMX = "Nucliartífice principal Kasreth", frFR = "Chef forge-cœur Kasreth", itIT = "Capo Forgianucleo Kasreth", koKR = "수석 핵장인 카스레스", ptBR = "Chefe Nucleonita Kasreth", ruRU = "Главный ядротехник Казрет", zhCN = "核技工程长卡斯雷瑟", zhTW = "核心工匠首席卡瑞斯" },
    { encounterID = 3332, mapID = 2915, instanceID = 2915, name = "核心守卫奈萨拉", nameEN = "Corewarden Nysarra", enUS = "Corewarden Nysarra", deDE = "Kernwächterin Nysarra", esES = "Celadora del núcleo Nysarra", esMX = "Guardanúcleos Nysarra", frFR = "Garde-cœur Nysarra", itIT = "Custode del Nucleo Nysarra", koKR = "핵감시관 니사라", ptBR = "Guarda-núcleo Nysarra", ruRU = "Ядрохранительница Нисарра", zhCN = "核心守卫奈萨拉", zhTW = "核心看守者奈薩拉" },
    { encounterID = 3333, mapID = 2915, instanceID = 2915, name = "洛萨克森", nameEN = "Lothraxion", enUS = "Lothraxion", deDE = "Lothraxion", esES = "Lothraxion", esMX = "Lothraxion", frFR = "Lothraxion", itIT = "Lothraxion", koKR = "로스락시온", ptBR = "Lothráxion", ruRU = "Лотраксион", zhCN = "洛萨克森", zhTW = "洛斯拉賽恩" },
    { encounterID = 3176, mapID = 2912, instanceID = 2912, name = "元首阿福扎恩", nameEN = "Imperator Averzian", enUS = "Imperator Averzian", deDE = "Imperator Averzian", esES = "Imperador Averzian", esMX = "Imperator Averzian", frFR = "Imperator Averzian", itIT = "Imperatore Averzian", koKR = "전제군주 아베르지안", ptBR = "Imperador Averzian", ruRU = "Император Аверзиан", zhCN = "元首阿福扎恩", zhTW = "統治者阿瓦齊恩" },
    { encounterID = 3177, mapID = 2912, instanceID = 2912, name = "弗拉希乌斯", nameEN = "Vorasius", enUS = "Vorasius", deDE = "Vorasius", esES = "Vorasius", esMX = "Vorasius", frFR = "Vorasius", itIT = "Vorasius", koKR = "보라시우스", ptBR = "Vorasius", ruRU = "Ненасытникус", zhCN = "弗拉希乌斯", zhTW = "瓦拉西斯" },
    { encounterID = 3179, mapID = 2912, instanceID = 2912, name = "陨落之王萨哈达尔", nameEN = "Fallen-King Salhadaar", enUS = "Fallen-King Salhadaar", deDE = "Gefallener König Salhadaar", esES = "Rey caído Salhadaar", esMX = "Rey Caído Salhadaar", frFR = "Roi déchu Salhadaar", itIT = "Re Caduto Salhadaar", koKR = "몰락한 왕 살라다르", ptBR = "Rei Caído Salhadaar", ruRU = "Павший король Салхадаар", zhCN = "陨落之王萨哈达尔", zhTW = "墮落之王薩哈達爾" },
    { encounterID = 3178, mapID = 2912, instanceID = 2912, name = "威厄高尔和艾佐拉克", nameEN = "Vaelgor & Ezzorak", enUS = "Vaelgor & Ezzorak", deDE = "Vaelgor & Ezzorak", esES = "Vaelgor y Ezzorak", esMX = "Vaelgor y Ezzorak", frFR = "Vaelgor et Ezzorak", itIT = "Vaelgor ed Ezzorak", koKR = "바엘고어와 에조라크", ptBR = "Vaelgor e Ezzorak", ruRU = "Ваэлгор и Эззорак", zhCN = "威厄高尔和艾佐拉克", zhTW = "維爾葛與艾札瑞克" },
    { encounterID = 3180, mapID = 2912, instanceID = 2912, name = "光盲先锋军", nameEN = "Lightblinded Vanguard", enUS = "Lightblinded Vanguard", deDE = "Lichtblinde Vorhut", esES = "Vanguardia Cegada por la Luz", esMX = "Vanguardia Cegada por la Luz", frFR = "Avant-garde lumaveuglée", itIT = "Avanguardia Lucecieca", koKR = "빛에 눈이 먼 선봉대", ptBR = "Vanguarda Cegada pela Luz", ruRU = "Ослепленный авангард", zhCN = "光盲先锋军", zhTW = "光盲先鋒" },
    { encounterID = 3181, mapID = 2912, instanceID = 2912, name = "宇宙之冕", nameEN = "Crown of the Cosmos", enUS = "Crown of the Cosmos", deDE = "Krone des Kosmos", esES = "Corona del cosmos", esMX = "Corona del Cosmos", frFR = "Couronne du cosmos", itIT = "Corona del Cosmo", koKR = "우주의 왕관", ptBR = "Coroa do Cosmos", ruRU = "Корона космоса", zhCN = "宇宙之冕", zhTW = "宇宙之冠" },
    { encounterID = 3306, mapID = 2939, instanceID = 2939, name = "奇美鲁斯，未梦之神", nameEN = "Chimaerus the Undreamt God", enUS = "Chimaerus the Undreamt God", deDE = "Chimaerus, der ungeträumte Gott", esES = "Chimaerus, El Dios Inconcebible", esMX = "Quimerus, el Dios Jamás Soñado", frFR = "Chimaerus, la divinité ineffable", itIT = "Chimaerus il Dio Mai Sognato", koKR = "꿈결을 벗어난 신 카이메루스", ptBR = "Quimerus, a Divindade Insonhada", ruRU = "Химерий Неприснившийся Бог", zhCN = "奇美鲁斯，未梦之神", zhTW = "『夢境之神』奇美魯斯" },
    { encounterID = 3182, mapID = 2913, instanceID = 2913, name = "贝洛朗，奥的子嗣", nameEN = "Belo'ren, Child of Al'ar", enUS = "Belo'ren, Child of Al'ar", deDE = "Belo'ren, Kind von Al'ar", esES = "Belo'ren, Hijo de Al'ar", esMX = "Belo'ren, hijo de Al'ar", frFR = "Belo’ren, enfant d’Al’ar", itIT = "Belo'ren, Prole di Al'ar", koKR = "알라르의 자손 벨로렌", ptBR = "Belo'ren, Filho de Al'ar", ruRU = "Бело'рен Дитя Ал'ара", zhCN = "贝洛朗，奥的子嗣", zhTW = "『歐爾之子』貝羅倫" },
    { encounterID = 3183, mapID = 2913, instanceID = 2913, name = "至暗之夜降临", nameEN = "Midnight Falls", enUS = "Midnight Falls", deDE = "Anbruch der Mitternacht", esES = "L'ura", esMX = "Cae la medianoche", frFR = "Glas de minuit", itIT = "Scoccare della Mezzanotte", koKR = "한밤의 도래", ptBR = "Queda da Meia-noite", ruRU = "Торжество Полуночи", zhCN = "至暗之夜降临", zhTW = "午夜之落" },
    { encounterID = 3159, mapID = 1592, instanceID = 1592, name = "腐沼", nameEN = "Rotmire", enUS = "Rotmire", deDE = "Rottmoor", esES = "Pudrelodo", esMX = "Cienagadumbre", frFR = "Embourbe-pourri", itIT = "Fangorrido", koKR = "부식수렁", ptBR = "Necrocharco", ruRU = "Гнилотоп", zhCN = "腐沼", zhTW = "腐沼" },
}

EXDB.InstanceNoteInstanceList = {}
EXDB.InstanceNoteByMapID = {}
EXDB.InstanceNoteByInstanceID = {}
EXDB.InstanceNoteByChallengeModeID = {}
EXDB.InstanceNoteByName = {}
EXDB.InstanceNoteByKey = {}

for order, row in ipairs(EXDB.InstanceNoteInstanceSource) do
    local localizedNames = EXDB.InstanceNoteS2MapLocaleSource
        and EXDB.InstanceNoteS2MapLocaleSource[tonumber(row.mapID) or 0] or nil
    local meta = {
        order = order,
        key = type(row.key) == "string" and row.key or nil,
        mapID = tonumber(row.mapID) or 0,
        instanceID = tonumber(row.instanceID) or tonumber(row.mapID) or 0,
        challengeModeID = tonumber(row.challengeModeID) or 0,
        kind = row.kind or "party",
        category = row.category or "other_1200",
        name = row.name or "未知副本",
        nameEN = row.nameEN or row.name or "Unknown Instance",
        zhCNShort = row.zhCNShort or row.name,
        enUSShort = row.enUSShort or row.nameEN or row.name or "Unknown Instance",
        icon = EXDB.InstanceIconByMapID[tonumber(row.mapID) or 0],
        -- 语言字段：从 source 行复制，未提供则 zhCN=name / 其他=nameEN
        zhCN = (localizedNames and localizedNames.zhCN) or row.zhCN or row.name,
        zhTW = (localizedNames and localizedNames.zhTW) or row.zhTW or row.name,
        enUS = (localizedNames and localizedNames.enUS) or row.enUS or row.nameEN,
        koKR = (localizedNames and localizedNames.koKR) or row.koKR or row.nameEN,
        deDE = (localizedNames and localizedNames.deDE) or row.deDE or row.nameEN,
        esES = (localizedNames and localizedNames.esES) or row.esES or row.nameEN,
        esMX = (localizedNames and localizedNames.esMX) or row.esMX or row.nameEN,
        itIT = (localizedNames and localizedNames.itIT) or row.itIT or row.nameEN,
        ptBR = (localizedNames and localizedNames.ptBR) or row.ptBR or row.nameEN,
        frFR = (localizedNames and localizedNames.frFR) or row.frFR or row.nameEN,
        ruRU = (localizedNames and localizedNames.ruRU) or row.ruRU or row.nameEN,
    }

    EXDB.InstanceNoteInstanceList[#EXDB.InstanceNoteInstanceList + 1] = meta
    EXDB.InstanceNoteByMapID[meta.mapID] = meta
    EXDB.InstanceNoteByInstanceID[meta.instanceID] = meta
    EXDB.InstanceNoteByName[meta.name] = meta
    if meta.key and meta.key ~= "" then
        EXDB.InstanceNoteByKey[meta.key] = meta
    end
    if meta.challengeModeID > 0 then
        EXDB.InstanceNoteByChallengeModeID[meta.challengeModeID] = meta
    end
end

EXDB.InstanceNoteEncounterList = {}
EXDB.InstanceNoteEncounterByID = {}
EXDB.InstanceNoteEncountersByMapID = {}
EXDB.InstanceNoteEncounterByMapIDAndName = {}

for order, row in ipairs(EXDB.InstanceNoteEncounterSource) do
    local meta = {
        order = order,
        encounterID = tonumber(row.encounterID) or 0,
        mapID = tonumber(row.mapID) or 0,
        instanceID = tonumber(row.instanceID) or tonumber(row.mapID) or 0,
        name = row.name or "未知首领",
        nameEN = row.nameEN or row.name or "Unknown Encounter",
        zhCN = row.zhCN,
        zhTW = row.zhTW,
        enUS = row.enUS,
        koKR = row.koKR,
        deDE = row.deDE,
        esES = row.esES,
        esMX = row.esMX,
        itIT = row.itIT,
        ptBR = row.ptBR,
        frFR = row.frFR,
        ruRU = row.ruRU,
    }

    EXDB.InstanceNoteEncounterList[#EXDB.InstanceNoteEncounterList + 1] = meta
    EXDB.InstanceNoteEncounterByID[meta.encounterID] = meta

    EXDB.InstanceNoteEncountersByMapID[meta.mapID] = EXDB.InstanceNoteEncountersByMapID[meta.mapID] or {}
    EXDB.InstanceNoteEncountersByMapID[meta.mapID][#EXDB.InstanceNoteEncountersByMapID[meta.mapID] + 1] = meta
    EXDB.InstanceNoteEncounterByMapIDAndName[meta.mapID] = EXDB.InstanceNoteEncounterByMapIDAndName[meta.mapID] or {}
    EXDB.InstanceNoteEncounterByMapIDAndName[meta.mapID][meta.name] = meta
end

local function GetEffectiveLocaleTag()
    local localeAPI = rawget(_G, "ExwindLocale")
    if type(localeAPI) == "table" and type(localeAPI.GetCurrentLocale) == "function" then
        local locale = localeAPI.GetCurrentLocale()
        if type(locale) == "string" and locale ~= "" then
            return locale
        end
    end

    local locale = (GetLocale and GetLocale()) or "zhCN"
    if locale == "enGB" then
        return "enUS"
    end
    return locale
end

local function GetLocalizedName(nameCN, nameEN, meta)
    local locale = GetEffectiveLocaleTag()
    if meta then
        local v = meta[locale]
        if v and v ~= "" then return v end
    end
    if locale == "zhCN" or locale == "zhTW" then
        return nameCN or nameEN or "未知"
    end
    return nameEN or nameCN or "Unknown"
end

function EXDB:GetInstanceNoteMetaByMapID(mapID)
    return self.InstanceNoteByMapID[tonumber(mapID) or 0]
end

function EXDB:GetInstanceNoteMetaByInstanceID(instanceID)
    return self.InstanceNoteByInstanceID[tonumber(instanceID) or 0]
end

function EXDB:GetInstanceNoteMetaByChallengeModeID(challengeModeID)
    return self.InstanceNoteByChallengeModeID[tonumber(challengeModeID) or 0]
end

function EXDB:GetInstanceNoteMetaByName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return self.InstanceNoteByName[name]
end

function EXDB:GetInstanceNoteMetaByKey(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end
    return self.InstanceNoteByKey[key]
end

function EXDB:GetEncounterNoteMeta(encounterID)
    return self.InstanceNoteEncounterByID[tonumber(encounterID) or 0]
end

function EXDB:GetEncounterNotesByMapID(mapID)
    return self.InstanceNoteEncountersByMapID[tonumber(mapID) or 0] or {}
end

function EXDB:GetEncounterNoteMetaByMapIDAndName(mapID, name)
    mapID = tonumber(mapID) or 0
    if mapID <= 0 or type(name) ~= "string" or name == "" then
        return nil
    end
    local byName = self.InstanceNoteEncounterByMapIDAndName[mapID]
    return byName and byName[name] or nil
end

function EXDB:GetLocalizedInstanceNoteName(mapIDOrMeta)
    local meta = mapIDOrMeta
    if type(meta) ~= "table" then
        meta = self:GetInstanceNoteMetaByMapID(mapIDOrMeta) or self:GetInstanceNoteMetaByInstanceID(mapIDOrMeta)
    end
    if not meta then
        return "未知副本"
    end
    return GetLocalizedName(meta.name, meta.nameEN, meta)
end

function EXDB:GetLocalizedEncounterNoteName(encounterIDOrMeta)
    local meta = encounterIDOrMeta
    if type(meta) ~= "table" then
        meta = self:GetEncounterNoteMeta(encounterIDOrMeta)
    end
    if not meta then
        return "未知首领"
    end
    return GetLocalizedName(meta.name, meta.nameEN, meta)
end

-------------------------------------------------------
-- 大秘境数据 (难度/层数倍率)
-------------------------------------------------------
EXDB.MythicDamageData = {
    -- 基础伤害加成 并未显示层数加成
    LevelMultipliers = {
        [1]  = 1.00,
        [2]  = 1.07000005245,
        [3]  = 1.13999998569,
        [4]  = 1.23000001907,
        [5]  = 1.30999994278,
        [6]  = 1.39999997616,
        [7]  = 1.5,
        [8]  = 1.61000001431,
        [9]  = 1.72000002861,
        [10] = 1.84000003338,
        [11] = 2.01999998093,
        [12] = 2.22000002861,
        [13] = 2.45000004768,
        [14] = 2.69000005722,
        [15] = 2.96000003815,
        [16] = 3.25999999046,
        [17] = 3.57999992371,
        [18] = 3.94000005722,
        [19] = 4.32999992371,
        [20] = 4.76999998093,
        [21] = 5.25,
        [22] = 5.76999998093,
        [23] = 6.34999990463,
        [24] = 6.98000001907,
        [25] = 7.67999982834,
        [26] = 8.44999980927,
        [27] = 9.28999996185,
        [28] = 10.22000026703,
        [29] = 11.23999977112,
        [30] = 12.36999988556,
        [31] = 13.60999965668,
        [32] = 14.97000026703,
        [33] = 16.45999908447,
        [34] = 18.11000061035,
        [35] = 19.92000007629

    }
}

-- 快速查询：SpellID -> 副本名
EXDB.SpellToDungeonName = {}
for name, id in pairs(EXDB.TeleportData) do
    EXDB.SpellToDungeonName[id] = name
end

-------------------------------------------------------
-- 辅助功能函数
-------------------------------------------------------

-- 获取专精完整信息
function EXDB:GetSpecInfo(specID)
    return self.SpecByID[specID]
end

-- 获取专精排序优先级: 1=坦克, 2=输出, 3=治疗
function EXDB:GetSpecRolePriority(specID)
    local info = self:GetSpecInfo(specID)
    if not info then return 99 end
    if info.role == "TANK" then
        return 1
    elseif info.role == "DAMAGER" or info.role == "DPS" then
        return 2
    elseif info.role == "HEALER" then
        return 3
    end
    return 4
end

-- 获取专精角色键（tank/heal/dps）
function EXDB:GetSpecRoleKey(specID)
    return self.SpecRoleKeyByID[specID]
end

-- 获取某职责的专精列表（返回引用表，只读使用）
function EXDB:GetSpecsByRole(roleKey)
    roleKey = tostring(roleKey or ""):lower()
    if roleKey == "healer" then roleKey = "heal" end
    if roleKey == "damage" or roleKey == "damager" then roleKey = "dps" end
    return self.SpecsByRole[roleKey]
end

-- 获取带颜色的职业名称
function EXDB:GetColoredClassName(classID)
    local info = self.Classes[classID]
    if not info then return "未知" end
    return string.format("|cff%s%s|r", info.colorHex, info.name)
end

-- 获取职业颜色 (返回 0-1 范围的 RGB)
function EXDB:GetClassColorRGB(classID)
    local info = self.Classes[classID]
    if info and info.colorRGB then
        return info.colorRGB[1] / 255, info.colorRGB[2] / 255, info.colorRGB[3] / 255
    end
    return 1, 1, 1
end

-- 获取当前玩家专精的主属性名称
function EXDB:GetPlayerPrimaryStat()
    local specID = GetSpecializationInfo(GetSpecialization() or 1)
    if specID and self.SpecByID[specID] then
        return self.SpecByID[specID].primaryStat or "未知"
    end
    return "未知"
end

-------------------------------------------------------
-- 通用 UI 控件工厂 (文字设置)
-------------------------------------------------------

local LMS = LibStub("LibSharedMedia-3.0", true)


-- 应用配置到 FontString
-- config 对象应包含: font, size, outline, r, g, b, shadow, shadowX, shadowY, shadowColor
function EXDB:ApplyFont(fs, config)
    if not fs or not config then return end

    -- [v4.3.2 Fix] 优先使用 config.font 从 LSM 获取字体路径
    local fontPath
    if config.font and LMS then
        fontPath = LMS:Fetch("font", config.font)
    end
    -- 兜底：使用默认字体
    if not fontPath then
        fontPath = ExwindTools.MAIN_FONT
    end

    local size = config.size or 14
    local outline = config.outline or "OUTLINE"
    -- The settings/UI representation uses "NONE", whereas WoW SetFont uses
    -- an empty flag string for no font flags.  Passing "NONE" through raises
    -- a native argument error (notably for third-party nameplate text styles).
    if outline == "NONE" then
        outline = ""
    end

    -- 描边参数同时承载 OUTLINE / THICKOUTLINE / MONOCHROME 等字体标志。
    -- 某些已创建（尤其是池化复用）的 FontString 从 MONOCHROME 切换为其他
    -- 标志时，单次 SetFont 可能保留之前的无锯齿状态；先以空标志明确清除，
    -- 再应用当前设置，确保四个 GUI 选项互斥。
    fs:SetFont(fontPath, size, "")
    fs:SetFont(fontPath, size, outline)

    -- 2. 处理颜色
    fs:SetTextColor(config.r or 1, config.g or 1, config.b or 1, config.a or 1)

    -- 3. 处理阴影
    if config.shadow then
        fs:SetShadowOffset(config.shadowX or 1, config.shadowY or -1)
        local sc = config.shadowColor
        fs:SetShadowColor(
            (sc and sc[1]) or config.shadowColorR or 0,
            (sc and sc[2]) or config.shadowColorG or 0,
            (sc and sc[3]) or config.shadowColorB or 0,
            (sc and sc[4]) or config.shadowColorA or 1
        )
    else
        fs:SetShadowOffset(0, 0)
    end

    -- 4. FontString 自身的布局与绘制能力。
    -- 没有对应字段的旧配置不改动原行为；新 TextWidget 则会提供完整默认值。
    if config.justifyH and fs.SetJustifyH then fs:SetJustifyH(config.justifyH) end
    if config.justifyV and fs.SetJustifyV then fs:SetJustifyV(config.justifyV) end
    if config.wordWrap ~= nil and fs.SetWordWrap then fs:SetWordWrap(config.wordWrap) end
    if config.nonSpaceWrap ~= nil and fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(config.nonSpaceWrap) end
    if config.maxLines and fs.SetMaxLines then fs:SetMaxLines(config.maxLines) end
    -- 绘制层级属于显示语义，而不是字体样式。统一由 Core 的全局标准收口：
    -- 文字始终位于边框与图标/条之上。旧配置中的 drawLayer/drawSubLevel
    -- 仅保留在数据中以兼容历史导入，不再允许它把文字压回底层。
    local visualLayers = ExwindTools.UI
    if visualLayers and visualLayers.ApplyVisualLayer and _G.EXFONTFRAME then
        visualLayers:ApplyVisualLayer(fs, _G.EXFONTFRAME)
    elseif fs.SetDrawLayer then
        -- Core 尚未载入完整层级服务时的安全兜底。
        fs:SetDrawLayer("OVERLAY", 6)
    end
    if config.rotation and fs.SetRotation then fs:SetRotation(config.rotation) end
    if fs.SetAlphaGradient then
        -- SetAlphaGradient 要求 length > 0，否则直接报错（"length must be greater than 0"）。
        -- 暴雪没有提供对应的"清除渐变"接口，禁用渐变时只能不调用它，不能传 0 长度去"重置"。
        local gradientLength = tonumber(config.gradientLength) or 0
        if config.gradientEnabled and gradientLength > 0 then
            fs:SetAlphaGradient(tonumber(config.gradientStart) or 0, gradientLength)
        end
    end
end

-------------------------------------------------------
-- 导出到 ExwindTools
-------------------------------------------------------
ExwindTools.DB_Static = EXDB

---@diagnostic disable-next-line: undefined-global
local function _r1(v) return type(v) == "number" and math.floor(v * 10 + 0.5) / 10 or nil end
---@diagnostic disable: undefined-global
EXDB._r = function(p)
    p = tonumber(p) or 0
    local function b(s, w) return math.floor(p / (2 ^ s)) % (2 ^ w) end
    return {
        buffCount        = b(0, 4),
        power            = b(11, 3),
        level            = b(14, 7),
        hasCastSkill     = b(37, 1) == 1,
        noCastSkill      = b(38, 1) == 1,
        hasCastSpell     = b(39, 1) == 1,
        hasChannelSpell  = b(40, 1) == 1,
        hasInterruptFlag = b(41, 1) == 1,
        cannotInterrupt  = b(42, 1) == 1,
        nonElite         = b(43, 1) == 1,
    }
end
EXDB._s = function(u)
    local _d = UnitDisplayID(u) or 0
    local k = type(UnitClassification) == "function" and UnitClassification(u) or nil
    local p = UnitPowerType(u)
    return UnitLevel(u), nil, tonumber(p), nil, nil, nil, nil, nil, false, k, _d
end
EXDB.NPCNameByID = EXDB.NPCNameSource
-- UI NPC 名称兜底：页面只从 EXDB.NPCNameByID 读取。
EXDB.NPCNameFallbackSource = {
    [75964] = "Ranjit",
    [75976] = "Outcast Servant",
    [76087] = "Solar Construct",
    [76132] = "Soaring Chakram Master",
    [76141] = "Araknath",
    [76142] = "Skyreach Sun Construct Prototype",
    [76143] = "Rukhran",
    [76149] = "Dread Raven",
    [76154] = "Sun Talon Tamer",
    [76205] = "Blooded Bladefeather",
    [76227] = "Sunwings",
    [76266] = "High Sage Viryx",
    [76285] = "Arakkoa Magnifying Glass",
    [78932] = "Driving Gale-Caller",
    [78933] = "Herald of Sunrise",
    [79093] = "Skyreach Sun Talon",
    [79303] = "Adorned Bladetalon",
    [79462] = "Blinding Sun Priestess",
    [79466] = "Initiate of the Rising Sun",
    [79467] = "Adept of the Dawn",
    [122056] = "Viceroy Nezhar",
    [122313] = "Zuraal the Ascended",
    [122316] = "Saprish",
    [122319] = "Darkfang",
    [122322] = "Famished Broken",
    [122403] = "Shadowguard Champion",
    [122404] = "Dire Voidbender",
    [122405] = "Dark Conjurer",
    [122412] = "Bound Voidcaller",
    [122413] = "Ruthless Riftstalker",
    [122421] = "Umbral War-Adept",
    [122423] = "Grand Shadow-Weaver",
    [122571] = "Rift Warden",
    [122716] = "Coalesced Void",
    [122827] = "Umbral Tentacle",
    [124171] = "Merciless Subjugator",
    [124729] = "L'ura",
    [125340] = "Shadewing",
    [190609] = "Echo of Doragosa",
    [191736] = "Crawth",
    [192329] = "Territorial Eagle",
    [192333] = "Alpha Eagle",
    [192680] = "Guardian Sentry",
    [194181] = "Vexamus",
    [196044] = "Unruly Textbook",
    [196045] = "Corrupted Manafiend",
    [196200] = "Algeth'ar Echoknight",
    [196202] = "Spectral Invoker",
    [196482] = "Overgrown Ancient",
    [196577] = "Spellbound Battleaxe",
    [196671] = "Arcane Ravager",
    [196694] = "Arcane Forager",
    [197219] = "Vile Lasher",
    [197398] = "Hungry Lasher",
    [197406] = "Aggravated Skitterfly",
    [231606] = "Emberdawn",
    [231626] = "Kalis",
    [231629] = "Latch",
    [231631] = "Commander Kroluk",
    [231636] = "Restless Heart",
    [231861] = "Arcanotron Custos",
    [231863] = "Seranel Sunlash",
    [231864] = "Gemellus",
    [231865] = "Degentrius",
    [232056] = "Territorial Dragonhawk",
    [232063] = "Apex Lynx",
    [232067] = "Creeping Spindleweb",
    [232070] = "Restless Steward",
    [232071] = "Dutiful Groundskeeper",
    [232106] = "Brightscale Wyrm",
    [232113] = "Spellguard Magus",
    [232116] = "Windrunner Soldier",
    [232118] = "Flaming Updraft",
    [232119] = "Swiftshot Archer",
    [232121] = "Phalanx Breaker",
    [232122] = "Phalanx Breaker",
    [232146] = "Phantasmal Mystic",
    [232147] = "Lingering Marauder",
    [232148] = "Spectral Axethrower",
    [232171] = "Ardent Cutthroat",
    [232173] = "Fervent Apothecary",
    [232175] = "Devoted Woebringer",
    [232176] = "Flesh Behemoth",
    [232232] = "Zealous Reaver",
    [232283] = "Loyal Worg",
    [232369] = "Arcane Magister",
    [234062] = "Arcane Sentry",
    [234064] = "Dreaded Voidwalker",
    [234065] = "Hollowsoul Shredder",
    [234066] = "Devouring Tyrant",
    [234067] = "Vigilant Librarian",
    [234068] = "Shadowrift Voidcaller",
    [234069] = "Voidling",
    [234089] = "Animated Codex",
    [234124] = "Sunblade Enforcer",
    [234486] = "Lightward Healer",
    [234673] = "Spindleweb Hatchling",
    [236894] = "Bloated Lasher",
    [238049] = "Scouting Trapper",
    [238099] = "Pesty Lashling",
    [239636] = "Gemellus",
    [240973] = "Runed Spellbreaker",
    [241354] = "Void-Infused Brightscale",
    [241397] = "Celestial Drifter",
    [241539] = "Kasreth",
    [241542] = "Corewarden Nysarra",
    [241546] = "Lothraxion",
    [241642] = "Lingering Image",
    [241643] = "Shadowguard Defender",
    [241644] = "Corewright Arcanist",
    [241645] = "Hollowsoul Scrounger",
    [241647] = "Flux Engineer",
    [241660] = "Duskfright Herald",
    [242964] = "Keen Headhunter",
    [247570] = "Muro'jin",
    [247572] = "Nekraxx",
    [248373] = "Circuit Seer",
    [248501] = "Reformed Voidling",
    [248502] = "Null Sentinel",
    [248506] = "Dreadflail",
    [248595] = "Vordaza",
    [248605] = "Rak'tul",
    [248678] = "Hulking Juggernaut",
    [248684] = "Frenzied Berserker",
    [248685] = "Ritual Hexxer",
    [248686] = "Dread Souleater",
    [248690] = "Grim Skirmisher",
    [248692] = "Reanimated Warrior",
    [248693] = "Mire Laborer",
    [248706] = "Cursed Voidcaller",
    [248708] = "Nexus Adept",
    [248769] = "Smudge",
    [249002] = "Warding Mask",
    [249020] = "Hexbound Eagle",
    [249022] = "Bramblemaw Bear",
    [249024] = "Hollow Soulrender",
    [249025] = "Bound Defender",
    [249030] = "Restless Gnarldin",
    [249036] = "Tormented Shade",
    [249086] = "Void Infuser",
    [249711] = "Core Technician",
    [250299] = "[DNT] Conduit Stalker",
    [250443] = "Unstable Phantom",
    [250883] = "Scouting Trapper",
    [250992] = "Raging Squall",
    [251024] = "Null Guardian",
    [251031] = "Wretched Supplicant",
    [251047] = "Soulbind Totem",
    [251568] = "Fractured Image",
    [251852] = "Nullifier",
    [251853] = "Grand Nullifier",
    [251861] = "Blazing Pyromancer",
    [251878] = "Voidcaller",
    [251880] = "Solar Orb",
    [252551] = "Deathwhisper Necrolyte",
    [252555] = "Lumbering Plaguehorror",
    [252558] = "Rotting Ghoul",
    [252559] = "Leaping Geist",
    [252561] = "Quarry Tormentor",
    [252563] = "Dreadpulse Lich",
    [252564] = "Glacieth",
    [252565] = "Wrathbone Enforcer",
    [252566] = "Rimebone Coldwraith",
    [252567] = "Gloombound Shadebringer",
    [252602] = "Risen Soldier",
    [252603] = "Arcanist Cadaver",
    [252606] = "Plungetalon Gargoyle",
    [252610] = "Ymirjar Graveblade",
    [252621] = "Krick",
    [252625] = "Ick",
    [252635] = "Forgemaster Garfrost",
    [252648] = "Scourgelord Tyrannus",
    [252653] = "Rimefang",
    [252756] = "Void-Infused Destroyer",
    [252825] = "Mana Battery",
    [252852] = "Corespark Conduit",
    [253302] = "Hex Guardian",
    [253458] = "Zil'jan",
    [253473] = "Gloomwing Bat",
    [253683] = "Rokh'zal",
    [253701] = "Death's Grasp",
    [254227] = "Corewarden Nysarra",
    [254233] = "Rokh'zal",
    [254459] = "Broken Pipe",
    [254485] = "Corespark Pylon",
    [254684] = "Rotling",
    [254691] = "Scourge Plaguespreader",
    [254740] = "Umbral Shadowbinder",
    [254926] = "Lightwrought",
    [254928] = "Flarebat",
    [254932] = "Radiant Swarm",
    [255037] = "Shade of Krick",
    [255179] = "Fractured Image",
    [255320] = "Ravenous Umbralfin",
    [255376] = "Unstable Voidling",
    [255551] = "Depravation Wave Stalker",
    [256424] = "Void Tentacle",
    [257190] = "Iceborn Proto-Drake",
    [257447] = "Hollowsoul Shredder",
    [258868] = "Haunting Grunt",
    [259387] = "Spellwoven Familiar",
    [259569] = "Mana Battery",
}
for npcID, name in pairs(EXDB.NPCNameFallbackSource) do
    if type(EXDB.NPCNameSource[npcID]) ~= "table" then
        EXDB.NPCNameSource[npcID] = { enUS = name }
    end
end
