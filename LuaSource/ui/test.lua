local SimpleDlg = require "simpledlg"
local testUmg = Inherit(SimpleDlg, UUserWidget)
testUmg:DynamicLoad("test")
function testUmg:Ctor(controller)
	self.Controller = controller
	self:Wnd("btn_clear"):Event("OnClicked", self.ClickClear, self)
	self:Wnd("Play"):Event("OnClicked", self.PlayAnim, self)

	local MaterialFather = UMaterial.LoadObject(self, "/Game/Git/mt_fog.mt_fog")
	self.MID = UKismetMaterialLibrary.CreateDynamicMaterialInstance(self, MaterialFather)

	self.MID:SetTextureParameterValue("tx_fog", controller.m_FogMgr.Tx_Fog)
	self:Wnd("img_fog"):SetBrushFromTexture(controller.m_FogMgr.Tx_Fog)

end
local hehe
function testUmg:PlayAnim()
	hehe = self.Controller.PlayCharacter.OnEndPlay
	hehe:Add(MakeCallBack(A_, "fuck you"))
end

function testUmg:ClickClear( )
	self.Controller.PlayCharacter:K2_DestroyActor()
	-- self.Controller:SpawnPlayer()
end

function testUmg:Txt1(content)
	self:Wnd("txt1"):SetText(tostring(content))
end

function testUmg:Txt2(content)
	self:Wnd("txt2"):SetText(tostring(content))
	-- self:Wnd("img_fog"):SetBrushFromMaterial(self.MID)
end

function testUmg:Txt3(content)
	self:Wnd("txt3"):SetText(tostring(content))
end

return testUmg