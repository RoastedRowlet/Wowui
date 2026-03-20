local env = select(2, ...)
local UIAnim_Engine = env.modules:Import("packages\\ui-anim\\engine")
local UIAnim_Methods = env.modules:Import("packages\\ui-anim\\methods")
local UIAnim_Enum = env.modules:Import("packages\\ui-anim\\enum")
local UIAnim = env.modules:New("packages\\ui-anim")

UIAnim.Enum = UIAnim_Enum
UIAnim.New = UIAnim_Engine.New
UIAnim.Animate = UIAnim_Engine.Animate
UIAnim.AnimateNumber = UIAnim_Methods.AnimateNumber
