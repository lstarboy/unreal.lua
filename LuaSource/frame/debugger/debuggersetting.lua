local DebuggerSetting = Inherit(CppObjectBase)

local DebuggerSingleton
local LuaSourceDir 
local BreakPoints
function DebuggerSetting:Ctor()
	LuaSourceDir = self:GetLuaSourceDir()
	DebuggerSingleton = self
	self.m_VarsIndex = 0
	local weakmeta = {__mode = "v"}
	self.m_WeakVars = setmetatable({}, weakmeta)
	self.m_bIsStart = false
	self.m_bIsDebuging = false
	self:Timer(self.Tick, self):Time(0.0001)
	self:PullDataToLua()
end

function DebuggerSetting:Tick( )
end

local Cached = {}
local function GetFullFilePath(Path)
	local TheCached = Cached[Path]
	if not TheCached then
		local FullPath = string.match(Path, ".*LuaSource(.*%.lua)")
		if FullPath then
			FullPath = string.gsub(FullPath, "\\", "/")
			Cached[Path] = LuaSourceDir..FullPath
			return FullPath
		end
		local LuaPath = string.match(Path, "%-%-%[%[(.-)%]%]")
		if LuaPath then
			LuaPath = string.gsub(LuaPath, "%.", "/")
			LuaPath = LuaSourceDir .. "/"..LuaPath .. ".lua"
			Cached[Path] = LuaPath
			return LuaPath
		end
		Cached[Path] = Path
		return Path
	else
		return TheCached
	end
end
local LuaPathCached = {}
local function GetLuaPath(Path)
	local TheCached = LuaPathCached[Path]
	if not TheCached then
		local FullPath = string.match(Path, ".*LuaSource/(.*)%.lua")
		if FullPath == nil then
			FullPath = Path
		end
		FullPath = string.gsub(FullPath, "/", ".")
		LuaPathCached[Path] = FullPath
		return FullPath
	else
		return TheCached
	end
end

local function IsHitBreakPoint(FilePath, Line)
	local Set = BreakPoints[FilePath]
	if Set then
		return Set[Line] == true
	else
		return false
	end
end

local getinfo = debug.getinfo
local function CollectStackData()
	local Contents={}
	local FilePaths={}
	local Lines={}
	local StackIndexs={}
	for i = 3, math.huge do
		local StackInfo = getinfo(i)
		if not StackInfo then break end
		local FilePath = GetFullFilePath(StackInfo.short_src)
		local Line = StackInfo.currentline
		local LuaPath = GetLuaPath(FilePath)
		local Content = LuaPath..":"..tostring(StackInfo.name).." Line"..tostring(Line)
		table.insert(Contents, Content)
		table.insert(FilePaths, FilePath)
		table.insert(Lines, Line)
		table.insert(StackIndexs, i)
	end
	DebuggerSingleton:SetStackData(Contents, Lines, FilePaths, StackIndexs)
end

local function HookCallBack(Event, Line)
	local StackInfo = getinfo(2)
	local FilePath = GetFullFilePath(StackInfo.short_src)
	if IsHitBreakPoint(FilePath, Line) then
		CollectStackData()
		DebuggerSingleton:EnterDebug(FilePath, Line)
	end
end

function DebuggerSetting:CheckToRun()
	local function ShouldRunDebug()
		return self.m_bIsTabOpen and self.m_bIsStart and self:HasAnyBreakPoint()
	end
	if self.m_bIsDebuging then
		if not ShouldRunDebug() then
			debug.sethook()
			self.m_bIsDebuging = false
		end	
	else
		if ShouldRunDebug() then
			debug.sethook(HookCallBack, "l")
			self.m_bIsDebuging = true
		end	
	end
end

function DebuggerSetting:ToggleDebugStart(bIsStart)
	self.m_bIsStart = bIsStart
	self:CheckToRun()
end

function DebuggerSetting:UpdateBreakPoint(BreakPoint)
	BreakPoints = BreakPoint
	self:CheckToRun()
end

function DebuggerSetting:SetTabIsOpen(bIsTabOpen)
	self.m_bIsTabOpen = bIsTabOpen
	self:CheckToRun()
end

function DebuggerSetting:HasAnyBreakPoint( )
	if BreakPoints then
		for FilePath, LineSet in pairs(BreakPoints) do
			for LineNum in pairs(LineSet) do
				return true
			end
		end
	end
	return false
end

local function GetClassName(VarValue)
	local name = ""
	if type(VarValue) == "table" or type(VarValue) == "userdata" then
		local function getname()
			if VarValue.classname then
				name = "("..VarValue.classname..")"
			end
		end
		-- lightweight userdata will error
		pcall(getname)
	end
	return name
end

local function IsContainer(Var)
	local classname = GetClassName(Var)
	if classname == "(ULuaArrayHelper)" or classname == "(ULuaSetHelper)" or classname == "(ULuaMapHelper)" then
		return true
	else
		return false
	end
end

local function MayHaveChildren(Var)
	local TheType = type(Var)
	if TheType == "table" or TheType == "userdata" then
		return true
	else
		return false
	end
end

function DebuggerSetting:AddToWeak(LuaValue)
	local index = self.m_VarsIndex +1
	self.m_VarsIndex = index
	if IsContainer(LuaValue) then
		LuaValue = LuaValue:Table()
	end
	self.m_WeakVars[index] = LuaValue
	return index
end

function DebuggerSetting:GetStackVars(StackIndex)
	local result = {}
	StackIndex = StackIndex + 2
	local StackInfo = getinfo(StackIndex, "f")
	local func = StackInfo.func
	if StackInfo and func then
		local function AddNode(name, value, isupvalue)
			local NewNode = FDebuggerVarNode.New()
			if MayHaveChildren(value) then
				local WeakIndex = self:AddToWeak(value)
				NewNode.ValueWeakIndex = WeakIndex
			end
			if isupvalue then
				name = name.."(upvalue)"
			end
			NewNode.Name = name
			NewNode.Value = tostring(value)..GetClassName(value)
			table.insert(result, NewNode)
		end
		for i = 1, math.huge do
			local name, value = debug.getupvalue(func, i)
			if not name then break end
			AddNode(name, value, true)
		end
		for i = 1, math.huge do
			local name, value = debug.getlocal(StackIndex, i)
			if not name then break end
			AddNode(name,value)
		end
	end
	return result
end

function DebuggerSetting:GetVarNodeChildren(ParentNode)
	local result = {}
	local Var = self.m_WeakVars[ParentNode.ValueWeakIndex]
	if Var then	
		local function AddNode(name, value)
			if type(value) == "function" then
				return
			end
			local NewNode = FDebuggerVarNode.New()
			if MayHaveChildren(value) then
				local WeakIndex = self:AddToWeak(value)
				NewNode.ValueWeakIndex = WeakIndex
			end
			NewNode.Name = name
			NewNode.Value = tostring(value)..GetClassName(value)
			table.insert(result, NewNode)
		end
		if type(Var) == "table" then
			local meta = getmetatable(Var)
			if meta then
				AddNode("$meta$", meta)
			end
			for name, value in pairs(Var) do 
				AddNode(name, value)
			end
			if meta then
				for key, v in pairs(meta) do
					if key:find("^LuaGet_") and type(v) == "function" then
						local name = key:match("^LuaGet_(.*)")
						local value = v(Var)
						AddNode(name, value)
					end
				end
			end
		elseif type(Var) == "userdata" then 
			local meta = getmetatable(Var)
			if meta then
				AddNode("$meta$", meta)
				for key, v in pairs(meta) do
					if key:find("^LuaGet_") and type(v) == "function" then
						local name = key:match("^LuaGet_(.*)")
						local value = v(Var)
						AddNode(name, value)
					end
				end
			end
		end
	end
	return result
end

function DebuggerSetting:Get( )
	return DebuggerSingleton
end

if UDebuggerSetting then
	DebuggerSetting:NewOn(UDebuggerSetting.Get())
end
return DebuggerSetting
