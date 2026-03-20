local env = select(2, ...)
local Sound = env.modules:Import("packages\\sound")
local UIFont = env.modules:Import("packages\\ui-font")
local UIKit = env.modules:Import("packages\\ui-kit")
local Frame, LayoutGrid, LayoutHorizontal, LayoutVertical, Text, ScrollContainer, LazyScrollContainer, ScrollBar, ScrollContainerEdge, Input, LinearSlider, HitRect, List = unpack(UIKit.UI.Frames)
local UICSharedMixin = env.modules:Import("packages\\uic-sharedmixin")
local GenericEnum = env.modules:Import("packages\\generic-enum")
local UICCommonPreload = env.modules:Import("packages\\uic-common\\preload")
local UICCommonButton = env.modules:New("packages\\uic-common\\button")

local Mixin = Mixin
local CreateFromMixins = CreateFromMixins

local UIDef = {
    Close                           = UICCommonPreload.ATLAS{ left = 319 / 512, right = 345 / 512, top = 185 / 512, bottom = 211 / 512 },
    SelectionMenu                   = UICCommonPreload.ATLAS{ left = 344 / 512, right = 370 / 512, top = 186 / 512, bottom = 212 / 512 },

    UIButtonRed                     = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 7 / 512, right = 100 / 512, top = 54 / 512, bottom = 95 / 512 },
    UIButtonRed_Highlighted         = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 106 / 512, right = 199 / 512, top = 54 / 512, bottom = 95 / 512 },
    UIButtonRed_Pushed              = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 205 / 512, right = 298 / 512, top = 54 / 512, bottom = 95 / 512 },
    UIButtonRed_Disabled            = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 304 / 512, right = 397 / 512, top = 54 / 512, bottom = 95 / 512 },
    UIButtonRedCompact              = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 7 / 512, right = 48 / 512, top = 148 / 512, bottom = 189 / 512 },
    UIButtonRedCompact_Highlighted  = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 54 / 512, right = 95 / 512, top = 148 / 512, bottom = 189 / 512 },
    UIButtonRedCompact_Pushed       = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 101 / 512, right = 142 / 512, top = 148 / 512, bottom = 189 / 512 },
    UIButtonRedCompact_Disabled     = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 148 / 512, right = 189 / 512, top = 148 / 512, bottom = 189 / 512 },

    UIButtonGray                    = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 7 / 512, right = 100 / 512, top = 7 / 512, bottom = 48 / 512 },
    UIButtonGray_Highlighted        = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 106 / 512, right = 199 / 512, top = 7 / 512, bottom = 48 / 512 },
    UIButtonGray_Pushed             = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 205 / 512, right = 298 / 512, top = 7 / 512, bottom = 48 / 512 },
    UIButtonGray_Disabled           = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 304 / 512, right = 397 / 512, top = 7 / 512, bottom = 48 / 512 },
    UIButtonGrayCompact             = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 7 / 512, right = 48 / 512, top = 101 / 512, bottom = 142 / 512 },
    UIButtonGrayCompact_Highlighted = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 54 / 512, right = 95 / 512, top = 101 / 512, bottom = 142 / 512 },
    UIButtonGrayCompact_Pushed      = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 101 / 512, right = 142 / 512, top = 101 / 512, bottom = 142 / 512 },
    UIButtonGrayCompact_Disabled    = UICCommonPreload.ATLAS{ inset = 14, scale = 0.7, left = 148 / 512, right = 189 / 512, top = 101 / 512, bottom = 142 / 512 }
}

do --Button
    local CONTENT_SIZE = UIKit.Define.Percentage{ value = 100, operator = "-", delta = 19 }
    local CONTENT_SIZE_SQUARE = UIKit.Define.Percentage{ value = 100 }
    local CONTENT_Y = 0
    local CONTENT_Y_HIGHLIGHTED = 0
    local CONTENT_Y_PRESSED = -1
    local CONTENT_ALPHA_ENABLED = 1
    local CONTENT_ALPHA_DISABLED = 0.5

    local ButtonMixin = CreateFromMixins(UICSharedMixin.ButtonMixin)

    function ButtonMixin:OnLoad(isRed, isCompact)
        self:InitButton()
        self.isRed = isRed
        self.isCompact = isCompact

        self:RegisterMouseEvents()
        self:HookButtonStateChange(self.UpdateAnimation)
        self:HookEnableChange(self.UpdateAnimation)
        self:HookMouseUp(self.PlayInteractSound)
        self:UpdateAnimation()
    end

    function ButtonMixin:UpdateAnimation()
        local isEnabled = self:IsEnabled()
        local buttonState = self:GetButtonState()

        if not isEnabled then
            local texture =
                self.isCompact and (self.isRed and UIDef.UIButtonRedCompact_Disabled or UIDef.UIButtonGrayCompact_Disabled) or
                (self.isRed and UIDef.UIButtonRed_Disabled or UIDef.UIButtonGray_Disabled)

            self.Texture:background(texture)
            self.Content:ClearAllPoints()
            self.Content:SetPoint("CENTER", self, "CENTER", 0, CONTENT_Y)
        elseif buttonState == "NORMAL" then
            local texture =
                self.isCompact and (self.isRed and UIDef.UIButtonRedCompact or UIDef.UIButtonGrayCompact) or
                (self.isRed and UIDef.UIButtonRed or UIDef.UIButtonGray)

            self.Texture:background(texture)
            self.Content:ClearAllPoints()
            self.Content:SetPoint("CENTER", self, "CENTER", 0, CONTENT_Y)
        elseif buttonState == "HIGHLIGHTED" then
            local texture =
                self.isCompact and (self.isRed and UIDef.UIButtonRedCompact_Highlighted or UIDef.UIButtonGrayCompact_Highlighted) or
                (self.isRed and UIDef.UIButtonRed_Highlighted or UIDef.UIButtonGray_Highlighted)

            self.Texture:background(texture)
            self.Content:ClearAllPoints()
            self.Content:SetPoint("CENTER", self, "CENTER", -CONTENT_Y_HIGHLIGHTED, CONTENT_Y_HIGHLIGHTED)
        elseif buttonState == "PUSHED" then
            local texture =
                self.isCompact and (self.isRed and UIDef.UIButtonRedCompact_Pushed or UIDef.UIButtonGrayCompact_Pushed) or
                (self.isRed and UIDef.UIButtonRed_Pushed or UIDef.UIButtonGray_Pushed)

            self.Texture:background(texture)
            self.Content:ClearAllPoints()
            self.Content:SetPoint("CENTER", self, "CENTER", -CONTENT_Y_PRESSED, CONTENT_Y_PRESSED)
        end

        self.Content:SetAlpha(isEnabled and CONTENT_ALPHA_ENABLED or CONTENT_ALPHA_DISABLED)
    end

    function ButtonMixin:PlayInteractSound()
        Sound.PlaySound("UI", SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end

    UICCommonButton.RedBase = UIKit.Template(function(id, name, children, ...)
        local frame =
            Frame(name, {
                Frame(name .. ".Content", {
                    unpack(children)
                })
                    :id("Content", id)
                    :point(UIKit.Enum.Point.Center)
                    :size(CONTENT_SIZE, CONTENT_SIZE)
                    :_updateMode(UIKit.Enum.UpdateMode.ExcludeVisibilityChanged)
            })
            :background(UIKit.UI.TEXTURE_NIL)
            :_updateMode(UIKit.Enum.UpdateMode.ExcludeVisibilityChanged)

        frame.Texture = frame:GetTextureFrame()
        frame.Content = UIKit.GetElementById("Content", id)

        Mixin(frame, ButtonMixin)
        frame:OnLoad(true)

        return frame
    end)

    UICCommonButton.GrayBase = UIKit.Template(function(id, name, children, ...)
        local frame =
            Frame(name, {
                Frame(name .. ".Content", {
                    unpack(children)
                })
                    :id("Content", id)
                    :point(UIKit.Enum.Point.Center)
                    :size(CONTENT_SIZE, CONTENT_SIZE)
                    :_updateMode(UIKit.Enum.UpdateMode.ExcludeVisibilityChanged)
            })
            :background(UIKit.UI.TEXTURE_NIL)
            :_updateMode(UIKit.Enum.UpdateMode.ExcludeVisibilityChanged)

        frame.Texture = frame:GetTextureFrame()
        frame.Content = UIKit.GetElementById("Content", id)

        Mixin(frame, ButtonMixin)
        frame:OnLoad(false)

        return frame
    end)

    UICCommonButton.RedBaseSquare = UIKit.Template(function(id, name, children, ...)
        local frame =
            Frame(name, {
                Frame(name .. ".Content", {
                    unpack(children)
                })
                    :id("Content", id)
                    :point(UIKit.Enum.Point.Center)
                    :size(CONTENT_SIZE_SQUARE, CONTENT_SIZE_SQUARE)
                    :_updateMode(UIKit.Enum.UpdateMode.ExcludeVisibilityChanged)
            })
            :background(UIKit.UI.TEXTURE_NIL)
            :_updateMode(UIKit.Enum.UpdateMode.ExcludeVisibilityChanged)

        frame.Texture = frame:GetTextureFrame()
        frame.Content = UIKit.GetElementById("Content", id)

        Mixin(frame, ButtonMixin)
        frame:OnLoad(true, true)

        return frame
    end)

    UICCommonButton.GrayBaseSquare = UIKit.Template(function(id, name, children, ...)
        local frame =
            Frame(name, {
                Frame(name .. ".Content", {
                    unpack(children)
                })
                    :id("Content", id)
                    :point(UIKit.Enum.Point.Center)
                    :size(CONTENT_SIZE_SQUARE, CONTENT_SIZE_SQUARE)
                    :_updateMode(UIKit.Enum.UpdateMode.ExcludeVisibilityChanged)
            })
            :background(UIKit.UI.TEXTURE_NIL)
            :_updateMode(UIKit.Enum.UpdateMode.ExcludeVisibilityChanged)

        frame.Texture = frame:GetTextureFrame()
        frame.Content = UIKit.GetElementById("Content", id)

        Mixin(frame, ButtonMixin)
        frame:OnLoad(false, true)

        return frame
    end)
end

do --Button (Text)
    local RED_TEXT_COLOR = GenericEnum.UIColorRGB.Normal
    local RED_TEXT_COLOR_HIGHLIGHTED = UIKit.Define.Color_RGBA{ r = 255, g = 255, b = 255, a = 1 }
    local GRAY_TEXT_COLOR = UIKit.Define.Color_RGBA{ r = 216, g = 216, b = 216, a = 1 }
    local GRAY_TEXT_COLOR_HIGHLIGHTED = UIKit.Define.Color_RGBA{ r = 255, g = 255, b = 255, a = 1 }

    local ButtonTextMixin = {}

    function ButtonTextMixin:ButtonText_OnLoad()
        self:HookButtonStateChange(self.ButtonText_UpdateAnimation)
    end

    function ButtonTextMixin:ButtonText_UpdateAnimation()
        local isRed = self.isRed
        local isEnabled = self:IsEnabled()
        local buttonState = self:GetButtonState()

        if not isEnabled then
            self.Text:textColor(isRed and RED_TEXT_COLOR or GRAY_TEXT_COLOR)
        elseif buttonState == "NORMAL" then
            self.Text:textColor(isRed and RED_TEXT_COLOR or GRAY_TEXT_COLOR)
        elseif buttonState == "HIGHLIGHTED" then
            self.Text:textColor(isRed and RED_TEXT_COLOR_HIGHLIGHTED or GRAY_TEXT_COLOR_HIGHLIGHTED)
        elseif buttonState == "PUSHED" then
            self.Text:textColor(isRed and RED_TEXT_COLOR_HIGHLIGHTED or GRAY_TEXT_COLOR_HIGHLIGHTED)
        end
    end

    function ButtonTextMixin:SetText(text)
        self.Text:SetText(text)
    end

    function ButtonTextMixin:GetText()
        return self.Text:GetText()
    end

    UICCommonButton.RedWithText = UIKit.Template(function(id, name, children, ...)
        local frame =
            UICCommonButton.RedBase(name, {
                Text(name .. ".Text")
                    :id("Text", id)
                    :fontObject(UIFont.UIFontObjectNormal12)
                    :textColor(RED_TEXT_COLOR)
                    :size(UIKit.UI.FILL)
                    :_updateMode(UIKit.Enum.UpdateMode.ExcludeVisibilityChanged),

                unpack(children)
            })
            :id("Button", id)

        frame.Text = UIKit.GetElementById("Text", id)

        Mixin(frame, ButtonTextMixin)
        frame:ButtonText_OnLoad()

        return frame
    end)

    UICCommonButton.GrayWithText = UIKit.Template(function(id, name, children, ...)
        local frame =
            UICCommonButton.GrayBase(name, {
                Text(name .. ".Text")
                    :id("Text", id)
                    :fontObject(UIFont.UIFontObjectNormal12)
                    :size(UIKit.UI.FILL)
                    :_updateMode(UIKit.Enum.UpdateMode.ExcludeVisibilityChanged),

                unpack(children)
            })

        frame.Text = UIKit.GetElementById("Text", id)

        Mixin(frame, ButtonTextMixin)
        frame:ButtonText_OnLoad()

        return frame
    end)
end

do --Button (Close)
    local SIZE = UIKit.Define.Percentage{ value = 62 }

    UICCommonButton.RedClose = UIKit.Template(function(id, name, children, ...)
        local frame =
            UICCommonButton.RedBaseSquare(name, {
                Frame(name .. ".Close")
                    :id("Close", id)
                    :point(UIKit.Enum.Point.Center)
                    :background(UIDef.Close)
                    :size(SIZE, SIZE)
                    :_updateMode(UIKit.Enum.UpdateMode.ExcludeVisibilityChanged),

                unpack(children)
            })

        frame.Close = UIKit.GetElementById("Close", id)
        frame.CloseTexture = frame.Close:GetTextureFrame()

        return frame
    end)
end

do --Button (Selection Menu)
    local ButtonSelectionMenuMixin = CreateFromMixins(UICSharedMixin.SelectionMenuRemoteMixin)

    function ButtonSelectionMenuMixin:OnLoad()
        self:InitSelectionMenuRemoteMixin()
    end

    UICCommonButton.SelectionMenu = UIKit.Template(function(id, name, children, ...)
        local frame =
            UICCommonButton.GrayWithText(name, {
                Frame(name .. ".Arrow")
                    :id("Arrow", id)
                    :point(UIKit.Enum.Point.Right)
                    :background(UIDef.SelectionMenu)
                    :size(12, 12)
                    :_updateMode(UIKit.Enum.UpdateMode.ExcludeVisibilityChanged),

                unpack(children)
            })

        frame.Text:textAlignment("LEFT", "MIDDLE")
        frame.Arrow = UIKit.GetElementById("Arrow", id)

        Mixin(frame, ButtonSelectionMenuMixin)
        frame:OnLoad()

        return frame
    end)
end
