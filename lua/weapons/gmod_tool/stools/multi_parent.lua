TOOL.Category		= "Constraints"
TOOL.Name			= "#tool.multi_parent.name"
TOOL.Command		= nil
TOOL.ConfigName		= ""
TOOL.Information	= {
	{ name = "left" },
	{ name = "right_parent", stage = 0 },
	{ name = "right_unparent", stage = 1 },
	{ name = "reload_unparenting", stage = 0 },
	{ name = "reload_parenting", stage = 1 },
}

TOOL.ClientConVar[ "removeconstraints" ] = "0"
TOOL.ClientConVar[ "nocollide" ] = "0"
TOOL.ClientConVar[ "disablecollisions" ] = "0"
TOOL.ClientConVar[ "weld" ] = "0"
TOOL.ClientConVar[ "weight" ] = "0"
TOOL.ClientConVar[ "radius" ] = "256"
TOOL.ClientConVar[ "disableshadow" ] = "0"

-- Language strings copied here to avoid having to send the file to clients
-- TODO: Remove this section and only use localization files if this ever gets uploaded to the Workshop
if CLIENT then
	language.Add("tool.multi_parent.name", "Multi-Parent")
	language.Add("tool.multi_parent.desc", "Parent multiple props to one prop.")

	language.Add("tool.multi_parent.left", "Select a prop (Shift to select all, Use to area select)")
	language.Add("tool.multi_parent.right_parent", "Parent all selected entities to prop")
	language.Add("tool.multi_parent.right_unparent", "Unparent all selected entities")
	language.Add("tool.multi_parent.reload_unparenting", "Clear targets (Shift to switch to unparenting mode)")
	language.Add("tool.multi_parent.reload_parenting", "Clear targets (Shift to switch to parenting mode)")

	language.Add("tool.multi_parent.autoselectradius", "Auto Select Radius:")
	language.Add("tool.multi_parent.removeconstraints", "Remove Constraints")
	language.Add("tool.multi_parent.nocollide", "No Collide")
	language.Add("tool.multi_parent.weld", "Weld")
	language.Add("tool.multi_parent.disablecollisions", "Disable Collisions")
	language.Add("tool.multi_parent.weight", "Set Weight")
	language.Add("tool.multi_parent.disableshadow", "Disable Shadows")

	language.Add("tool.multi_parent.removeconstraints.help", "Remove all constraints before parenting. This cannot be undone!")
	language.Add("tool.multi_parent.nocollide.help", "Checking this creates a no collide constraint between the entity and parent. Unchecking will save on constraints (read: lag) but you will have to area-copy to duplicate your contraption.")
	language.Add("tool.multi_parent.weld.help", "Checking this creates a weld between the entity and parent. This will retain the physics on parented props and you will still be able to physgun them, but it will cause more lag (not recommended).")
	language.Add("tool.multi_parent.disablecollisions.help", "Disable all collisions before parenting. Useful for props that are purely for visual effect.")
	language.Add("tool.multi_parent.weight.help", "Checking this will set the entity's weight to 0.1 before parenting. Useful for props that are purely for visual effect.")
	language.Add("tool.multi_parent.disableshadow.help", "Disables shadows for parented entities.")

	language.Add("Undone_Multi-Parent", "Undone Multi-Parent")
	language.Add("tool.multi_parent.notify", "Multi-Parent: %s entities were selected.")
end

function TOOL.BuildCPanel( panel )
	panel:AddControl( "Slider", {
		Label = "#tool.multi_parent.autoselectradius",
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

local function sendNotification( selected, ply )
	net.Start( "MultiParent_SendNotification" )
		net.WriteUInt( selected, MAX_EDICT_BITS )
	net.Send( ply )
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

		sendNotification( SelectedProps, ply )
	elseif ply:KeyDown( IN_SPEED ) then -- Select all constrained entities
		local SelectedProps = 0

		for _, v in pairs( constraint.GetAllConstrainedEntities( ent ) ) do
			self:Select( v )
			SelectedProps = SelectedProps + 1
		end

		sendNotification( SelectedProps, ply )
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

if SERVER then return end

local parentFrameColor = ColorAlpha( parentColor, parentColor.a + 50 )
local unparentFrameColor = ColorAlpha( unparentColor, unparentColor.a + 50 )
local shouldRenderAreaSelect = false
local curStage = 0
local curRadius = 64

function TOOL:Think()
	local ply = self:GetOwner()
	shouldRenderAreaSelect = ply:KeyDown( IN_USE )
	if not shouldRenderAreaSelect then return end

	curStage = self:GetStage()
	curRadius = math.Clamp( self:GetClientNumber( "radius" ), 64, 1024 )
end

hook.Add( "PostDrawTranslucentRenderables", "MultiParent_RenderAreaSelect", function( bDrawingDepth, _, isDraw3DSkybox )
	if not shouldRenderAreaSelect then return end
	if bDrawingDepth or isDraw3DSkybox then return end

	local pos = LocalPlayer():GetEyeTrace().HitPos
	local sphereQuality = 20
	local sphereColor = curStage == 0 and parentColor or unparentColor
	local frameColor = curStage == 0 and parentFrameColor or unparentFrameColor

	render.SetColorMaterial()
	render.DrawSphere( pos, curRadius, sphereQuality, sphereQuality, sphereColor )
	render.DrawWireframeSphere( pos, curRadius, sphereQuality, sphereQuality, frameColor, true )
end )

net.Receive( "MultiParent_SendNotification", function()
	local selected = net.ReadUInt( MAX_EDICT_BITS )
	local notifyText = language.GetPhrase( "tool.multi_parent.notify" )

	notification.AddLegacy( notifyText:format( selected ), NOTIFY_GENERIC, 5 )
end )