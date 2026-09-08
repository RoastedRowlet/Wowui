local existing = _G.EXWIND_CORE_DEPENDENCY_NOTICE
if existing then return end

local LOCALE_ALIASES = { enGB = "enUS", esMX = "esES", ptPT = "ptBR" }
local MESSAGES = {
    enUS = { title = "ExwindCore Required", missing = "The following add-ons cannot be enabled until ExwindCore is installed:\n\n%s\n\nSearch for EXCORE on your preferred add-on platform, install it, then reload the UI.", unavailable = "The following add-ons cannot be enabled because ExwindCore is disabled or failed to load:\n\n%s\n\nEnable ExwindCore, then reload the UI." },
    deDE = { title = "ExwindCore erforderlich", missing = "Die folgenden Add-ons können erst aktiviert werden, wenn ExwindCore installiert ist:\n\n%s\n\nSuche auf deiner bevorzugten Add-on-Plattform nach EXCORE, installiere es und lade die Benutzeroberfläche neu.", unavailable = "Die folgenden Add-ons können nicht aktiviert werden, weil ExwindCore deaktiviert ist oder nicht geladen werden konnte:\n\n%s\n\nAktiviere ExwindCore und lade die Benutzeroberfläche neu." },
    esES = { title = "Se requiere ExwindCore", missing = "Los siguientes complementos no se pueden activar hasta que instales ExwindCore:\n\n%s\n\nBusca EXCORE en tu plataforma de complementos preferida, instálalo y recarga la interfaz.", unavailable = "Los siguientes complementos no se pueden activar porque ExwindCore está desactivado o no se pudo cargar:\n\n%s\n\nActiva ExwindCore y recarga la interfaz." },
    frFR = { title = "ExwindCore requis", missing = "Les add-ons suivants ne peuvent pas être activés tant qu'ExwindCore n'est pas installé :\n\n%s\n\nRecherchez EXCORE sur votre plateforme d'add-ons préférée, installez-le, puis rechargez l'interface.", unavailable = "Les add-ons suivants ne peuvent pas être activés car ExwindCore est désactivé ou n'a pas pu être chargé :\n\n%s\n\nActivez ExwindCore, puis rechargez l'interface." },
    itIT = { title = "ExwindCore richiesto", missing = "I seguenti addon non possono essere attivati finché ExwindCore non è installato:\n\n%s\n\nCerca EXCORE sulla tua piattaforma di addon preferita, installalo e ricarica l'interfaccia.", unavailable = "I seguenti addon non possono essere attivati perché ExwindCore è disattivato o non è stato caricato:\n\n%s\n\nAttiva ExwindCore, quindi ricarica l'interfaccia." },
    koKR = { title = "ExwindCore 필요", missing = "다음 애드온을 사용하려면 ExwindCore를 설치해야 합니다:\n\n%s\n\n선호하는 애드온 플랫폼에서 EXCORE를 검색하여 설치한 후 UI를 다시 불러오세요.", unavailable = "다음 애드온은 ExwindCore가 비활성화되었거나 로드하지 못해 사용할 수 없습니다:\n\n%s\n\nExwindCore를 활성화한 후 UI를 다시 불러오세요." },
    ptBR = { title = "ExwindCore necessário", missing = "Os seguintes addons não podem ser ativados até que ExwindCore seja instalado:\n\n%s\n\nProcure EXCORE na sua plataforma de addons preferida, instale-o e recarregue a interface.", unavailable = "Os seguintes addons não podem ser ativados porque ExwindCore está desativado ou não pôde ser carregado:\n\n%s\n\nAtive ExwindCore e recarregue a interface." },
    ruRU = { title = "Требуется ExwindCore", missing = "Следующие аддоны нельзя включить, пока не установлен ExwindCore:\n\n%s\n\nНайдите EXCORE на предпочитаемой платформе аддонов, установите его и перезагрузите интерфейс.", unavailable = "Следующие аддоны нельзя включить, потому что ExwindCore отключён или не загрузился:\n\n%s\n\nВключите ExwindCore и перезагрузите интерфейс." },
    zhCN = { title = "需要 ExwindCore", missing = "以下插件需要安装 ExwindCore 后才能启用：\n\n%s\n\n请在各大插件平台搜索EXCORE并安装，然后重新载入界面。", unavailable = "以下插件无法启用，因为 ExwindCore 已被禁用或加载失败：\n\n%s\n\n请启用 ExwindCore，然后重新载入界面。" },
    zhTW = { title = "需要 ExwindCore", missing = "以下插件需要安裝 ExwindCore 後才能啟用：\n\n%s\n\n請在各大插件平台搜尋EXCORE並安裝，然後重新載入介面。", unavailable = "以下插件無法啟用，因為 ExwindCore 已被停用或載入失敗：\n\n%s\n\n請啟用 ExwindCore，然後重新載入介面。" },
}

local DOWNLOAD_LINKS = "\n\nCurseForge:\nhttps://www.curseforge.com/wow/addons/excore\n\nWago:\nhttps://addons.wago.io/addons/excore"

local registry = { products = {}, queued = false, printed = false }
_G.EXWIND_CORE_DEPENDENCY_NOTICE = registry

function registry:CreatePanel()
    local panel = CreateFrame("Frame", "EXWINDCoreDependencyNoticePanel", UIParent, "BackdropTemplate")
    panel:SetSize(680, 390)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", tile = true, tileSize = 32 })
    panel:SetBackdropColor(0.07, 0.05, 0.025, 0.98)

    local function CreateBorderLine()
        local line = panel:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(1, 1, 1, 0.9)
        return line
    end
    local top = CreateBorderLine()
    top:SetHeight(1)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    local bottom = CreateBorderLine()
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    local left = CreateBorderLine()
    left:SetWidth(1)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    local right = CreateBorderLine()
    right:SetWidth(1)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", 0, -42)
    title:SetTextColor(1, 0.82, 0)
    panel.title = title
    local header = panel:CreateTexture(nil, "BORDER")
    header:SetColorTexture(0.16, 0.10, 0.025, 0.9)
    header:SetHeight(52)
    header:SetPoint("TOPLEFT", 34, -28)
    header:SetPoint("TOPRIGHT", -34, -28)
    local message = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    message:SetPoint("TOPLEFT", 48, -108)
    message:SetPoint("BOTTOMRIGHT", -48, 80)
    message:SetJustifyH("CENTER")
    message:SetJustifyV("MIDDLE")
    message:SetWordWrap(true)
    panel.message = message
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(190, 34)
    button:SetPoint("BOTTOM", 0, 34)
    button:SetText(OKAY)
    button:SetScript("OnClick", function() panel:Hide() end)
    panel:Hide()
    self.panel = panel
end

function registry:Refresh()
    local names = {}
    for _, productName in pairs(self.products) do table.insert(names, productName) end
    table.sort(names)
    if #names == 0 then return end
    if not self.panel then self:CreatePanel() end
    local locale = LOCALE_ALIASES[GetLocale()] or GetLocale()
    local localized = MESSAGES[locale] or MESSAGES.enUS
    local key = C_AddOns.DoesAddOnExist("ExwindCore") and "unavailable" or "missing"
    local message = localized[key]:format(table.concat(names, "\n")) .. DOWNLOAD_LINKS
    self.panel.title:SetText(localized.title)
    self.panel.message:SetText(message)
    self.panel:Show()
    if not self.printed then print("[Exwind] " .. message); self.printed = true end
end

function registry:RegisterProduct(addonName, productName)
    self.products[addonName] = productName
    if self.queued then return end
    self.queued = true
    C_Timer.After(0, function() self.queued = false; self:Refresh() end)
end
