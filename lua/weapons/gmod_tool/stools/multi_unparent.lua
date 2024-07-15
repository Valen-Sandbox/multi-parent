TOOL.Category		= "Constraints"
TOOL.Name			= "#tool.multi_unparent.listname"
TOOL.Command		= nil
TOOL.ConfigName		= ""

local plytbl = {}

if CLIENT then
    language.Add( "tool.multi_unparent.name", "Multi-Unparent Tool" )
    language.Add( "tool.multi_unparent.listname", "Multi-Unparent" )
    language.Add( "tool.multi_unparent.desc", "Unparents multiple props." )
    language.Add( "tool.multi_unparent.0", "Primary: Select a prop. Secondary: Unparent all selected entities. Reload: Clear Targets." )
	
	local function Select() -- runs a trace on the client rather than the server so that it will reliably hit parented entities
		local tr = util.TraceLine( util.GetPlayerTrace(LocalPlayer()) )
		RunConsoleCommand( "unparent_select", tr.Entity:EntIndex() )
	end
	net.Receive( "unparent_select", Select )
end

if SERVER then 
	util.AddNetworkString( "unparent_select" )
	
	local function UnparentSelect( ply, cmd, args )
		local eid = args[1] or 0
		local ent = Entity( eid )
		if not IsValid( ent ) or ent:IsWorld() or ent:IsPlayer() then return end
		local uid = ply:UserID()
		
		plytbl[uid] = plytbl[uid] or {}
		local enttbl = plytbl[ply:UserID()] or {}
		
		if not enttbl[eid] then
			local col = Color(0, 0, 0, 0)
			col = ent:GetColor()
			enttbl[eid] = col
			ent:SetColor( Color(255, 0, 0, 100) )
			ent:SetRenderMode( RENDERMODE_TRANSALPHA )
		else
			local col = enttbl[eid]
			ent:SetColor( col )
			enttbl[eid] = nil
		end
	end
	concommand.Add( "unparent_select", UnparentSelect )
end

function TOOL:LeftClick( trace )
	if CLIENT then return true end
	
	net.Start( "unparent_select" )
	net.Send( self:GetOwner() )
	
	return true
end

function TOOL:RightClick( trace )
	if CLIENT then return true end
	
	local uid = self:GetOwner():UserID()
	local enttbl = plytbl[uid]
	
	if (not enttbl) or table.Count( enttbl ) < 1 then return false end
	
	for k, v in pairs( enttbl ) do
		local prop = Entity( k )
		if IsValid( prop ) then
			local phys = prop:GetPhysicsObject()
			if IsValid( phys ) then
				if IsValid( prop:GetParent() ) then -- don't unparent if ent is not parented
					
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
				enttbl[k] = nil
			end
		end
	end
	enttbl = {}
	return true
end

function TOOL:Reload()
	if CLIENT then return false end
	local uid = self:GetOwner():UserID()
	local enttbl = plytbl[uid]
	if (not enttbl) or table.Count( enttbl ) < 1 then return false end
	
	for k,v in pairs( enttbl ) do
		local prop = ents.GetByIndex( k )
		if prop:IsValid() then
			prop:SetColor( v )
			enttbl[k] = nil
		end
	end
	enttbl = {}
	return true
end