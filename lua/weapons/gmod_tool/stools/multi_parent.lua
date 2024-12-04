TOOL.Category		= "Constraints"
TOOL.Name			= "#tool.multi_parent.name"
TOOL.Command		= nil
TOOL.ConfigName		= ""
TOOL.Information	= {
	{ name = "left" },
	{ name = "right_parent", stage = 0 },
	{ name = "right_unparent", stage = 1 },
	{ name = "reload" },
	{ name = "reload_unparenting", stage = 0, icon2 = "gui/info" },
	{ name = "reload_parenting", stage = 1, icon2 = "gui/info" },
}

TOOL.ClientConVar[ "removeconstraints" ] = "0"
TOOL.ClientConVar[ "nocollide" ] = "0"
TOOL.ClientConVar[ "disablecollisions" ] = "0"
TOOL.ClientConVar[ "weld" ] = "0"
TOOL.ClientConVar[ "weight" ] = "0"
TOOL.ClientConVar[ "radius" ] = "512"
TOOL.ClientConVar[ "disableshadow" ] = "0"

function TOOL.BuildCPanel( panel )
	panel:AddControl( "Slider", {
		Label = "Auto Select Radius:",
		Type = "integer",
		Min = "64",
		Max = "1024",
		Command = "multi_parent_radius"
	} )
	panel:AddControl( "Checkbox", {
		Label = "#tool.multi_parent.removeconstraints",
		Command = "multi_parent_removeconstraints",
		Help = true
	} )
	panel:AddControl( "Checkbox", {
		Label = "#tool.multi_parent.nocollide",
		Command = "multi_parent_nocollide",
		Help = true
	} )
	panel:AddControl( "Checkbox", {
		Label = "#tool.multi_parent.weld",
		Command = "multi_parent_weld",
		Help = true
	} )
	panel:AddControl( "Checkbox", {
		Label = "#tool.multi_parent.disablecollisions",
		Command = "multi_parent_disablecollisions",
		Help = true
	} )
	panel:AddControl( "Checkbox", {
		Label = "#tool.multi_parent.weight",
		Command = "multi_parent_weight",
		Help = true
	} )
	panel:AddControl( "Checkbox", {
		Label = "#tool.multi_parent.disableshadow",
		Command = "multi_parent_disableshadow",
		Help = true
	} )
end

TOOL.entTbl = {}

function TOOL:IsPropOwner( ply, ent )
	if CPPI then
		return ent:CPPIGetOwner() == ply
	else
		for k, v in pairs( g_SBoxObjects ) do
			for _, j in pairs( v ) do
				for _, e in pairs( j ) do
					if e == ent and k == ply:UniqueID() then return true end
				end
			end
		end
	end

	return false
end

function TOOL:IsSelected( ent )
	local eid = ent:EntIndex()

	return self.entTbl[eid] ~= nil
end

local defaultColor = Color( 0, 0, 0, 0 )
local parentColor = Color( 0, 255, 0, 100 )
local unparentColor = Color( 255, 0, 0, 100 )

function TOOL:Select( ent )
	local eid = ent:EntIndex()

	if not self:IsSelected( ent ) then -- Select
		local oldColor = ent:GetColor() or defaultColor
		local newColor = self:GetStage() == 0 and parentColor or unparentColor

		self.entTbl[eid] = oldColor
		ent:SetColor( newColor )
		ent:SetRenderMode( RENDERMODE_TRANSALPHA )
	end
end

function TOOL:Deselect( ent )
	local eid = ent:EntIndex()

	if self:IsSelected( ent ) then -- Deselect
		local col = self.entTbl[eid]
		ent:SetColor( col )
		self.entTbl[eid] = nil
	end
end

function TOOL:ParentCheck( child, parent )
	while IsValid( parent ) do
		if child == parent then
			return false
		end

		parent = parent:GetParent()
	end

	return true
end

function TOOL:LeftClick( trace )
	local ent = trace.Entity

	if ent:IsValid() and ent:IsPlayer() then return end
	if SERVER and not util.IsValidPhysicsObject( ent, trace.PhysicsBone ) then return false end

	local ply = self:GetOwner()
	local inUse = ply:KeyDown( IN_USE )

	if not inUse and ent:IsWorld() then return false end
	if CLIENT then return true end

	if inUse then -- Area select function
		local SelectedProps = 0
		local Radius = math.Clamp( self:GetClientNumber( "radius" ), 64, 1024 )

		for _, v in ipairs( ents.FindInSphere( trace.HitPos, Radius ) ) do
			if v:IsValid() and not self:IsSelected( v ) and self:IsPropOwner( ply, v ) then
				self:Select( v )
				SelectedProps = SelectedProps + 1
			end
		end

		ply:PrintMessage( HUD_PRINTTALK, "Multi-Parent: " .. SelectedProps .. " props were selected." )
	elseif ply:KeyDown( IN_SPEED ) then -- Select all constrained entities
		local SelectedProps = 0

		for _, v in pairs( constraint.GetAllConstrainedEntities( ent ) ) do
			self:Select( v )
			SelectedProps = SelectedProps + 1
		end

		ply:PrintMessage( HUD_PRINTTALK, "Multi-Parent: " .. SelectedProps .. " props were selected." )
	elseif self:IsSelected( ent ) then -- Ent is already selected, deselect it
		self:Deselect( ent )
	else -- Select single entity
		self:Select( ent )
	end

	return true
end

local function unparentTargets( entTbl )
	if CLIENT then return end

	for k, v in pairs( entTbl ) do
		local prop = Entity( k )

		if IsValid( prop ) then
			local phys = prop:GetPhysicsObject()

			if IsValid( phys ) then
				if IsValid( prop:GetParent() ) then -- Don't unparent if ent is not parented

					-- Save some stuff because we want ent values not physobj values
					local pos = prop:GetPos()
					local ang = prop:GetAngles()
					local mat = prop:GetMaterial()
					local mass = phys:GetMass()

					-- Unparent
					phys:EnableMotion( false )
					prop:SetParent( nil )

					-- Restore values
					phys:SetMass( mass )
					prop:SetMaterial( mat )
					prop:SetAngles( ang )
					prop:SetPos( pos )
				end

				-- Deselect ent
				prop:SetColor( v )
				entTbl[k] = nil
			end
		end
	end

	entTbl = {}
end

function TOOL:RightClick( trace )
	local entTbl = self.entTbl

	if SERVER and table.Count( entTbl ) < 1 then return false end

	-- Unparenting mode behavior
	if self:GetStage() == 1 then
		unparentTargets( entTbl )

		return true
	end

	local ent = trace.Entity

	if ent:IsValid() and ent:IsPlayer() then return false end
	if SERVER and not util.IsValidPhysicsObject( ent, trace.PhysicsBone ) then return false end
	if ent:IsWorld() then return false end
	if CLIENT then return true end

	local _nocollide = tobool( self:GetClientNumber( "nocollide" ) )
	local _disablecollisions = tobool( self:GetClientNumber( "disablecollisions" ) )
	local _weld = tobool( self:GetClientNumber( "weld" ) )
	local _removeconstraints = tobool( self:GetClientNumber( "removeconstraints" ) )
	local _weight = tobool( self:GetClientNumber( "weight" ) )
	local _disableshadow = tobool( self:GetClientNumber( "disableshadow" ) )

	local undo_tbl = {}

	undo.Create( "Multi-Parent" )

	for k, v in pairs( entTbl ) do
		local prop = Entity( k )

		if IsValid( prop ) and self:ParentCheck( prop, ent ) then
			local phys = prop:GetPhysicsObject()

			if IsValid( phys ) then
				local data = {}

				if _removeconstraints then
					constraint.RemoveAll( prop )
				end

				if _nocollide then
					undo.AddEntity( constraint.NoCollide( prop, ent, 0, 0 ) )
				end

				if _disablecollisions then
					data.ColGroup = prop:GetCollisionGroup()
					prop:SetCollisionGroup( COLLISION_GROUP_WORLD )
				end

				if _weld then
					undo.AddEntity( constraint.Weld( prop, ent, 0, 0 ) )
				end

				if _weight then
					data.Mass = phys:GetMass()
					phys:SetMass( 0.1 )
					duplicator.StoreEntityModifier( prop, "mass", { Mass = 0.1 } )
				end

				if _disableshadow then
					data.DisabledShadow = true
					prop:DrawShadow( false )
				end

				-- Unfreeze and sleep the physobj
				phys:EnableMotion( true )
				phys:Sleep()

				-- Restore original color and parent
				prop:SetColor( v )
				prop:SetParent( ent )
				entTbl[k] = nil

				-- Undo shit
				undo_tbl[prop] = data
			end
		else
			-- Not going to parent, just deselect it
			if IsValid( prop ) then prop:SetColor( v ) end

			entTbl[k] = nil
		end
	end

	-- Unparenting function for undo
	undo.AddFunction( function()
		for prop, data in pairs( undo_tbl ) do
			if IsValid( prop ) then
				local phys = prop:GetPhysicsObject()

				if IsValid( phys ) then
					-- Save some stuff because we want ent values not physobj values
					local pos = prop:GetPos()
					local ang = prop:GetAngles()
					local mat = prop:GetMaterial()
					local col = prop:GetColor()

					-- Unparent
					phys:EnableMotion( false )
					prop:SetParent( nil )

					-- Restore values
					prop:SetColor( col )
					prop:SetMaterial( mat )
					prop:SetAngles( ang )
					prop:SetPos( pos )

					if data.Mass then
						phys:SetMass( data.Mass )
					end

					if data.ColGroup then
						prop:SetCollisionGroup( data.ColGroup )
					end

					if data.DisabledShadow then
						prop:DrawShadow( true )
					end
				end
			end
		end
	end, undo_tbl )

	undo.SetPlayer( self:GetOwner() )
	undo.Finish()

	self.entTbl = {}

	return true
end

function TOOL:Reload()
	local curStage = self:GetStage()
	local entTbl = self.entTbl

	-- Change to the other tool mode
	if self:GetOwner():KeyDown( IN_SPEED ) then
		self:SetStage( curStage == 0 and 1 or 0 )

		local newColor = curStage == 0 and unparentColor or parentColor

		-- Update colors of selected targets to match the new tool mode
		for k in pairs( entTbl ) do
			local prop = ents.GetByIndex( k )

			if prop:IsValid() then
				prop:SetColor( newColor )
			end
		end

		return false
	end

	if CLIENT then return true end
	if table.Count( entTbl ) < 1 then return false end

	for k, v in pairs( entTbl ) do
		local prop = ents.GetByIndex( k )

		if prop:IsValid() then
			prop:SetColor( v )
			entTbl[k] = nil
		end
	end

	self.entTbl = {}

	return true
end