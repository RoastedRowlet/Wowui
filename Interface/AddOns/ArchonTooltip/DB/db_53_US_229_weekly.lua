local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Unknown-Unknown','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Devourer','Shaman-Elemental','Rogue-Outlaw','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Druid-Guardian','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Enhancement','Monk-Windwalker','Rogue-Assassination','Monk-Brewmaster','Evoker-Devastation','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Mage-Arcane','DeathKnight-Unholy','Warrior-Fury','Paladin-Retribution','DemonHunter-Vengeance','Warrior-Arms','Warrior-Protection','Hunter-Marksmanship','Mage-Frost','Rogue-Subtlety','Warlock-Affliction','Evoker-Augmentation','Evoker-Preservation','Monk-Mistweaver','Paladin-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaralyn:BAAANQAECgEIAQAAAA==.',
Ab='Abmikaze:BAAANQADCggICgAAAA==.Absolon:BAAANQADCgMIAwABNQAECgUIBQABAAAAAA==.Abysseon:BAABNQAECoEYAAMCAAgKMxoZHQBWAgACAAgKMxoZHQBWAgADAAMKawuxjgCAAAAAAA==.',
Ac='Ace:BAAANQAECgUIDQAAAA==.',
Ad='Adios:BAACNQAFFIEPAAIEAAUKbg4SBQCeAQAEAAUKbg4SBQCeAQA1AAQKgSAAAgQACQpvHHUPANMCAAQACQpvHHUPANMCAAAA.Adorean:BAAANQAECgYIEQAAAA==.',
Ae='Aenymbria:BAAANQADCgQIBwAAAA==.',
Ag='Age:BAAANQAECgQICgAAAA==.Agrohn:BAAANQAECgQIBAAAAA==.',
Ai='Aimnskin:BAAANQADCggJEwAAAA==.',
Al='Alcore:BAAANQAECgYICwAAAA==.Aliine:BAAANQAECgUIDwAAAA==.',
Am='Ameiisaa:BAAANQAECgYIEAAAAA==.Amethaendron:BAAANQADCgcIDgAAAA==.Amneesia:BAAANQADCgQIBQAAAA==.Amytiel:BAABNQAECoExAAIFAAkKbh67GwD1AgAFAAkKbh67GwD1AgAAAA==.',
An='Anxie:BAAANQAECgcIDQAAAA==.Anìtamaxwynn:BAAANQADCgQIBAABNQAFFAYIEAAGACccAA==.',
Ao='Aoifae:BAAANQAECgQIBwAAAA==.',
Ap='Apickle:BAAANQADCggIDQAAAA==.Applecider:BAABNQAECoEYAAQHAAgKmAlScABfAQAHAAcKKApScABfAQAIAAcKdgfaMQBBAQAJAAEKMAX6JQApAAAAAA==.Apprentice:BAAANQAECgUICwAAAA==.',
Ar='Aramos:BAABNQAECoEZAAIKAAcKPBc4SQAAAgAKAAcKPBc4SQAAAgAAAA==.Aramôs:BAAANQAECgEIAQAAAA==.Arkhangel:BAAANQAECgUIDgAAAA==.Arta:BAAANQAECgEIAQAAAA==.',
As='Asgnomeus:BAAANQADCgUIBQAAAA==.Ashhealz:BAAANQAECgMICAAAAA==.',
At='Atraxx:BAAANQABCgMIBAAAAA==.',
Ax='Axlegrease:BAAANQADCgcIEgAAAA==.',
Az='Azuzu:BAAANQAECgEIAQABNQAECgkJIQADAF8PAA==.',
Ba='Balacarn:BAAANQAECgIIAwAAAA==.Barlok:BAAANQAECgQICgAAAA==.Barrywhite:BAAANQADCgEIAQAAAA==.',
Be='Beaker:BAABNQAECoEZAAILAAgK1w8HFQCOAQALAAgK1w8HFQCOAQAAAA==.Beastmode:BAABNQAECoEeAAMMAAgKThNPHgDkAQAMAAgKThNPHgDkAQANAAgKXg/WOADZAQAAAA==.Bedlem:BAAANQAECgUICQAAAA==.Beko:BAAANQAECgcIEAAAAA==.Belonna:BAAANQABCgEIAQAAAA==.Bendytwotime:BAAANQAECgYIBgAAAA==.Bernard:BAAANQADCgMIAwAAAA==.',
Bi='Bidoof:BAAANQAECgMIBwAAAA==.Billydan:BAAANQAECgcIEQAAAA==.',
Bl='Blackhide:BAAANQABCgMIBAAAAA==.Blackpanthxr:BAABNQAECoEfAAQOAAkKrQyWVADCAQAOAAkKrQyWVADCAQAPAAcKKAmeFgCeAQAFAAcKoAaQgwBEAQAAAA==.Blackvortex:BAAANQAECgQIBAAAAA==.Bloodgoat:BAAANQADCggICAAAAA==.Bloodsoul:BAAANQAECgMIBQAAAA==.Bloodybloodz:BAAANQADCggICAABNQAECggIGwAQAEIkAA==.Bloodyburst:BAABNQAECoEXAAMGAAgKPyJQBACcAgAGAAcKZSJQBACcAgARAAIK6hvmWgCwAAABNQAECggIGwAQAEIkAA==.Bloodyfistz:BAABNQAECoEbAAMQAAgKQiSpCgD8AgAQAAgKOSSpCgD8AgASAAIKMyO+GwDLAAAAAA==.Blue:BAABNQAECoEYAAIFAAgKGhjZLwB7AgAFAAgKGhjZLwB7AgAAAA==.Bluethreetwo:BAAANQAECgQIBgAAAA==.',
Bo='Bookofzeref:BAAANQADCgEIAQAAAA==.',
Br='Brayend:BAAANQAECgYJCQAAAA==.Brewguts:BAAANQAECgcIBwAAAA==.Brimscythe:BAABNQAECoEfAAITAAgKcxjKDABiAgATAAgKcxjKDABiAgAAAA==.Brutalx:BAAANQADCggICAAAAA==.',
By='Byebyeman:BAAANQADCgYIBgAAAA==.',
Ca='Calaveras:BAAANQABCggIDAAAAA==.Caliandis:BAAANQAECgUICwAAAA==.Calvey:BAAANQAECgMIAwAAAA==.Cambrai:BAAANQAECgQIBgAAAA==.Cannabelle:BAABNQAECoEdAAIUAAcKCSXvHADvAgAUAAcKCSXvHADvAgAAAA==.Carclias:BAABNQAECoEqAAMVAAkKeRdkCgA/AgAVAAgKBBdkCgA/AgAWAAcKyRQkZADbAQAAAA==.Carthrix:BAAANQAECgYIBgAAAA==.Catbarf:BAAANQADCggIBgABNQAECggIIAAPAMseAA==.Cathrix:BAAANQADCgUIBwAAAA==.Cattlerage:BAAANQAECgQICgAAAA==.',
Ce='Cellika:BAAANQAECgQICAAAAA==.Cerdelz:BAAANQAECgMIAwAAAA==.',
Ch='Chaoscookies:BAABNQAECoEdAAMVAAgKYBLkFwCfAQAVAAYKVRPkFwCfAQAWAAQK1At9xQDdAAAAAA==.Chartkov:BAAANQAECgEIAQAAAA==.Cheezee:BAABNQAFFIEGAAIXAAYKnAxbCgDkAQAXAAYKnAxbCgDkAQAAAA==.Chermer:BAAANQADCgQIBAAAAA==.Chibonesteak:BAAANQADCgYIBgAAAA==.Chubbytoyboy:BAAANQADCgYIBgABNQAECggIHAAXAE8QAA==.',
Ci='Cinderpetal:BAAANQAECgQIBQAAAA==.',
Ck='Ckay:BAAANQADCggJCAAAAA==.',
Cl='Clawsome:BAAANQADCggICAAAAA==.',
Co='Cobrakaidojo:BAAANQAECgYIBwAAAA==.Cohemew:BAABNQAECoEYAAQYAAkKXxQWQwCoAQAYAAcKVhQWQwCoAQACAAUKLREjRwAiAQADAAQK0guHewC9AAAAAA==.Comlock:BAAANQADCgYIDAAAAA==.Complacent:BAAANQAECgYIDwAAAA==.Comrage:BAAANQABCgYIBAAAAA==.Comspyder:BAAANQAECgEIAQAAAA==.Coriander:BAAANQAECgcIEwAAAA==.Corii:BAAANQADCgMJAwAAAA==.Cosmo:BAAANQAECgQIBQABNQAECgUICgABAAAAAA==.',
Ct='Cthùlhù:BAAANQADCggICAAAAA==.',
Cu='Cursedchild:BAAANQAECggIDgABNQAFFAYIEwAQAJgYAA==.',
Cy='Cynical:BAAANQADCgYIBgABNQAECgUIDQABAAAAAA==.Cyonicus:BAAANQAECgYIEQAAAA==.Cyska:BAABNQAECoEhAAIDAAkKXw+OPQDJAQADAAkKXw+OPQDJAQAAAA==.',
['Cé']='Cécé:BAAANQAECgYIDgAAAA==.',
['Cë']='Cëcë:BAAANQADCgMICQAAAA==.',
Da='Dababayaga:BAAANQAECgEJAQAAAA==.Dabz:BAAANQAECgUIDwAAAA==.Daciana:BAAANQADCgYIBgAAAA==.Dagaroonie:BAAANQAECgMIAwAAAA==.Dagerlaurn:BAAANQAECgcIEQAAAA==.Dagevas:BAAANQADCgYIBgAAAA==.Dakeria:BAAANQADCgYIFQAAAA==.Darkando:BAAANQADCgcIDQAAAA==.Darksoldier:BAAANQAECgYIEAAAAA==.Darthfire:BAAANQABCgYICAAAAA==.Dartoy:BAEBNQAECoEaAAIZAAgKHw6lCgDRAQAZAAgKHw6lCgDRAQABNQAFFAMIBwAaANYbAA==.Dax:BAAANQAECgQIBgAAAA==.Daxing:BAAANQADCggIFAABNQAECggIEgABAAAAAA==.',
De='Deeppurple:BAAANQAECgEIAQAAAA==.Del:BAABNQAECoEcAAIbAAgKACZDAQB9AwAbAAgKACZDAQB9AwAAAA==.Demoniaca:BAAANQADCgEIAQAAAA==.Demonic:BAAANQAECgEIAQABNQAECgUIDQABAAAAAA==.Demonshady:BAAANQABCggIEQAAAA==.Demoraliziñg:BAAANQADCggIDgAAAA==.Demostache:BAABNQAECoEnAAMWAAkKXCFAHADkAgAWAAgKxyBAHADkAgAVAAIKyRVkRgCYAAABNQAECgkJGAAYAF8UAA==.Derevi:BAAANQADCgcIBwAAAA==.Despot:BAAANQAECgUICAAAAA==.',
Dh='Dhargal:BAABNQAECoEbAAIFAAgK/R4XJAC9AgAFAAgK/R4XJAC9AgAAAA==.',
Do='Dolomite:BAAANQAECgYIDQAAAA==.Dorow:BAABNQAECoEbAAMNAAkK/xcbLAA4AgANAAgKHRgbLAA4AgAMAAIKwwgTTQB1AAABNQAECgkJGAAQACUZAA==.Dotabolt:BAAANQAECgYIEQAAAA==.',
Dr='Dracthyris:BAAANQAECgcIBwAAAA==.Dragonash:BAAANQADCgYIBgAAAA==.Draéne:BAAANQADCgcIEAAAAA==.Dreaa:BAAANQADCgUICwAAAA==.Drinkme:BAAANQADCgEIAQAAAA==.Droki:BAABNQAECoEgAAIPAAgKyx7MBwDVAgAPAAgKyx7MBwDVAgAAAA==.',
Du='Dunsel:BAAANQAECgQIBwABNQAECggIHwATAHMYAA==.Dunwich:BAAANQADCgIIAgAAAA==.Duulket:BAAANQAECgQIBAAAAA==.',
Dy='Dyanna:BAAANQABCgYICgAAAA==.',
['Dà']='Dànny:BAABNQAECoEZAAMcAAcKGRXXfwDHAQAcAAcKGRXXfwDHAQAdAAIKYw2oLQBZAAAAAA==.',
['Dã']='Dãnny:BAAANQADCgEIAQABNQAECgcIGQAcABkVAA==.',
Eb='Ebonshade:BAAANQADCggIGAAAAA==.',
Ed='Edena:BAAANQADCgEIAQAAAA==.Edginglord:BAAANQAECgMIBAAAAA==.Edya:BAAANQADCgIIAgAAAA==.',
El='Elgringo:BAAANQADCgEIAQABNQADCgYICwABAAAAAA==.Eloras:BAAANQAECgEIAgAAAA==.Elunbi:BAABNQAECoEmAAMHAAgKKh8MHgDDAgAHAAgKdB4MHgDDAgAJAAYKkhSiCgBrAQAAAA==.',
Em='Emovoker:BAAANQADCgYIBAAAAA==.Emshady:BAAANQADCggICQAAAA==.',
Ep='Epsilòn:BAEANQAECggIEAAAAA==.',
Er='Ernest:BAAANQAECgMIAwAAAA==.Errani:BAAANQAECgQICQAAAA==.',
Es='Esper:BAAANQAECgYICAAAAA==.',
Eu='Eureki:BAAANQAECgUIBgAAAA==.',
Ev='Evilkarma:BAAANQAECgUICQAAAA==.Evocatis:BAABNQAECoEcAAMaAAkKciNeGAA8AwAaAAkKciNeGAA8AwAKAAIKEQft1QBuAAAAAA==.',
Ey='Eyekonicklok:BAAANQADCgYJBgAAAA==.Eyesdeadeyed:BAABNQAECoEiAAIeAAkKvBJTHQAtAgAeAAkKvBJTHQAtAgAAAA==.',
Fa='Fabullous:BAAANQAECgMIAwAAAA==.Faion:BAAANQAECgYIEQAAAA==.Falco:BAAANQAECggIAQAAAA==.Faon:BAAANQADCgEIAQAAAA==.Farrea:BAAANQADCggIEQAAAA==.Fatlock:BAAANQAECgIIAgABNQAECggIIAAQAE4bAA==.Fayvia:BAAANQABCggIDQAAAA==.',
Fe='Feebz:BAAANQADCgYIBwAAAA==.Felzbirt:BAAANQAECgEIAQAAAA==.Feorely:BAAANQAECgcIEgAAAA==.',
Fi='Fire:BAAANQAECgEIAQABNQAECgUIDQABAAAAAA==.Firebirdz:BAAANQAFFAIIAwAAAA==.',
Fl='Flygon:BAAANQAECgcICAAAAA==.',
Fo='Forque:BAAANQADCgYICAAAAA==.',
Fr='Frater:BAAANQADCgEIAQAAAA==.Frequentine:BAAANQAECgYIEwAAAA==.Friargark:BAAANQADCgUIBQAAAA==.Frizby:BAAANQAECgEIAQAAAA==.Frostypaw:BAAANQADCgIIAgAAAA==.',
Fu='Fuzzybut:BAAANQAECgQICAAAAA==.',
Fy='Fyrelord:BAAANQAECgEIAQAAAA==.Fyuna:BAABNQAECoEZAAIOAAgK/Rw5JACcAgAOAAgK/Rw5JACcAgAAAA==.',
Ga='Gark:BAAANQAECgEIAQAAAA==.Garkk:BAAANQADCgQJBAAAAA==.Gazzi:BAAANQAECgcIEgAAAA==.',
Ge='Genevieve:BAAANQAECgEIAQABNQAECgQICQABAAAAAA==.',
Gi='Gióvanna:BAAANQAECgIIAgAAAA==.',
Gl='Glodskegg:BAAANQAECgcIEgAAAA==.',
Go='Goldensea:BAAANQAECgMIBwAAAA==.Gotenk:BAAANQAECgUIBwAAAA==.Goyim:BAAANQAECgQIBQAAAA==.',
Gr='Gr:BAAANQADCgMIBwAAAA==.Grissoul:BAAANQABCgQIBAAAAA==.Grody:BAAANQAECgUICwAAAA==.',
Gu='Guroo:BAABNQAECoEaAAIUAAcKfgtNgACrAQAUAAcKfgtNgACrAQAAAA==.',
['Gá']='Gárp:BAAANQAECgEIAQAAAA==.',
Ha='Hagarn:BAABNQAECoEhAAIaAAgKXBP6agABAgAaAAgKXBP6agABAgAAAA==.Halimah:BAAANQAECgQICQAAAA==.Halois:BAAANQADCgYIBgABNQAECgYIFgADAPETAA==.Hardtwosee:BAAANQAECggIDQAAAA==.Harleypaw:BAAANQAECggICAAAAA==.Hazan:BAAANQAECggICAABNQAECggIIAAPAMseAA==.',
He='Hexmachine:BAABNQAECoEeAAIWAAkK6QzwZwDPAQAWAAkK6QzwZwDPAQAAAA==.',
Ho='Hole:BAAANQADCgYJBgAAAA==.Holyflem:BAAANQADCggICAAAAA==.',
Hu='Huntzcatzup:BAAANQAECgEIAQAAAA==.',
Hy='Hypertext:BAAANQAECgYICAAAAA==.',
Ia='Iamahriman:BAAANQAECgYIDwAAAA==.Iamarawn:BAAANQAECgQICAAAAA==.',
Ig='Ignite:BAABNQAECoEbAAMXAAkK9himbQBwAgAXAAgKMBmmbQBwAgAfAAEKJxe9MQBHAAAAAA==.',
Il='Illestria:BAABNQAECoEZAAIaAAcKoxNPgwC7AQAaAAcKoxNPgwC7AQAAAA==.Illumiscotty:BAABNQAECoEhAAMXAAkKhiQ2CwCeAwAXAAkKhiQ2CwCeAwAfAAEKzBjKMgBEAAAAAA==.',
In='Incognonetoo:BAAANQAECgcICAAAAA==.Insania:BAAANQAECgYICwAAAA==.',
Ir='Ironhands:BAAANQADCgYIBgAAAA==.',
Iz='Izara:BAAANQADCgYIFgAAAA==.',
Ja='Jamizi:BAAANQADCgcIBwAAAA==.Jaspally:BAAANQADCggJDgABNQAECggIEgABAAAAAA==.Jastirri:BAAANQAECgUIBwAAAA==.',
Ji='Jimbojonesjr:BAAANQAECgIIAwAAAA==.Jimothy:BAAANQADCgYIBgABNQABCgQIAgABAAAAAA==.',
Jo='Johneringo:BAAANQAECgEJAQAAAA==.Jonjee:BAAANQAECgcIEgAAAA==.',
Ju='Juicez:BAAANQAECgEIAQAAAA==.Jurkee:BAAANQADCgYICwAAAA==.',
Ka='Kahekili:BAAANQADCgYICgAAAA==.Kain:BAAANQAECgcIBQAAAA==.Kalak:BAAANQABCgIIAgAAAA==.Kaleielin:BAAANQAECggIDwAAAA==.Katio:BAABNQAECoEgAAMRAAgKxR5bMwCTAQARAAQKfCJbMwCTAQAgAAQKDhvmKABLAQAAAA==.Kayanna:BAAANQADCgQIBAAAAA==.Kayhless:BAAANQAECgUICQAAAA==.Kazunt:BAAANQABCgQIBAAAAA==.',
Ke='Kershneep:BAAANQAECgEIAQAAAA==.Kessandra:BAACNQAFFIERAAMWAAYKGB5CAgAkAgAWAAYKtR1CAgAkAgAhAAEK8CL/BABhAAA1AAQKgR0AAyEACQpGJBoBADUDACEACQr7IhoBADUDABYABQqcHOuCAH4BAAAA.Kexally:BAAANQADCggIHQAAAA==.Kexkan:BAAANQADCgQIDAABNQADCggIHQABAAAAAA==.Kezzia:BAAANQADCgMIAwAAAA==.',
Kh='Khurri:BAAANQAECgcIEgAAAA==.',
Ki='Kiarah:BAAANQAECgIIBAAAAA==.Kiliin:BAAANQAECggICAAAAA==.Killplz:BAAANQADCgYIFQAAAA==.Kirr:BAAANQAFFAEIAQAAAA==.Kisor:BAAANQADCgMIAwAAAA==.Kitchenstink:BAAANQAECgcIEgAAAA==.',
Ko='Koifo:BAAANQABCgUIBQAAAA==.Korvath:BAAANQADCgIIAgAAAA==.',
Kp='Kplaow:BAAANQABCggICgAAAA==.',
Kr='Kritanta:BAABNQAECoEWAAIDAAYK8RM+UQBqAQADAAYK8RM+UQBqAQAAAA==.Krystallus:BAAANQAECgIIAgAAAA==.',
Ku='Kurnea:BAAANQAECgQIBgAAAA==.',
['Kó']='Kórrá:BAAANQADCgMIAwAAAA==.',
La='Lachlann:BAAANQAECgQIBwAAAA==.Lakartó:BAABNQAECoEoAAQTAAgKDB0ECwCNAgATAAgKEhwECwCNAgAiAAUK3BojCgB5AQAjAAEKWB/NPQBVAAAAAA==.Laleaf:BAAANQABCggIEAAAAA==.Laura:BAAANQABCgEIAQAAAA==.Law:BAAANQAECgMIAwAAAA==.',
Ld='Ldritch:BAACNQAFFIEHAAMRAAQKYRr2CQC6AAAgAAIKJhzeCQDHAAARAAIKmxj2CQC6AAA1AAQKgSAABCAACQpFJCkUACUCACAABgqBIykUACUCABEABQryI9glAPcBAAYAAQo/GR4WAEsAAAAA.',
Le='Leifson:BAAANQAECgUIBwAAAA==.Leonedis:BAAANQAECgQICQAAAA==.Lethea:BAAANQADCgYICQAAAA==.Levious:BAAANQAECgUIDQAAAA==.',
Li='Lianara:BAAANQADCgQJCAABNQAECgEIAQABAAAAAA==.Lidorisse:BAAANQADCgYIBgAAAA==.',
Lo='Lovedoctor:BAAANQABCgUIBQAAAA==.',
Lu='Ludo:BAABNQAECoEmAAIPAAkKICHWAgBkAwAPAAkKICHWAgBkAwAAAA==.Lukri:BAAANQADCgcICAAAAA==.Lumisbrew:BAABNQAECoEcAAMkAAgK4hcnDwBFAgAkAAgK4hcnDwBFAgAQAAEK8gqKUQA5AAAAAA==.Luxurious:BAAANQAECgYIDgAAAA==.',
Ma='Maaca:BAAANQADCgYICgAAAA==.Maecarepicha:BAAANQAECgUIBQAAAA==.Malachor:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Maligned:BAAANQAECgYIBwAAAA==.Martichoux:BAAANQAECgcIEgAAAA==.Mastakronik:BAAANQABCgIIAwAAAA==.Match:BAAANQAECgMIAwAAAA==.Mathas:BAABNQAECoEiAAQKAAkK6hoYGADuAgAKAAkK6hoYGADuAgAaAAIKeAfJLQFWAAAlAAEKpw7lWgAqAAAAAA==.Mathilda:BAAANQAECgIJAgAAAA==.',
Mc='Mccholock:BAAANQAECgQICgAAAA==.Mcmach:BAAANQAECgYIBgAAAA==.',
Me='Meddox:BAAANQABCggIDQAAAA==.Mehaoloka:BAAANQADCgcICgAAAA==.Memelle:BAAANQAECgUICwAAAA==.Menoah:BAAANQAECgUICQAAAA==.Menotthatorc:BAAANQADCgIIAgABNQAECgkJGAAYAF8UAA==.Merdoc:BAAANQAECgQJBAAAAA==.Meredith:BAAANQAECgQICQAAAA==.Mesilana:BAAANQADCggIDAAAAA==.Metrx:BAAANQADCgUIBQAAAA==.',
Mi='Miltank:BAAANQADCgYIDAAAAA==.Mirenna:BAAANQAECgUICwAAAA==.Misseymiss:BAAANQADCgIIAgAAAA==.Mithian:BAAANQADCgMJAwAAAA==.',
Mo='Mogwhy:BAAANQADCgYIBgAAAA==.Molbeato:BAAANQAECgMIAwAAAA==.Monichan:BAAANQADCggICwAAAA==.Moosecheeks:BAAANQAECgcIDgAAAA==.Morganna:BAAANQABCggIDQAAAA==.Morior:BAAANQAECgUICQAAAA==.Morslucifer:BAABNQAECoEWAAMhAAcKZByIBABPAgAhAAcKZByIBABPAgAVAAEKehMwZgA/AAAAAA==.Motorcade:BAAANQAECgYICgAAAA==.',
Mu='Murazor:BAAANQAECgEIAQAAAA==.Mutent:BAAANQADCgYIDAAAAA==.',
My='Mypal:BAAANQAECgMIAwAAAA==.Myrelis:BAAANQAFFAEIAQAAAA==.',
['Mû']='Mûrasaki:BAAANQABCgQIBQAAAA==.',
Na='Naula:BAAANQADCgcIDgAAAA==.',
Ne='Neather:BAAANQAECgUIBwAAAA==.Neron:BAAANQADCgUICQAAAA==.Nezkima:BAAANQADCgQIBAABNQAECgkJHAAOACgfAA==.',
Ni='Nidivh:BAAANQAECgEIAQAAAA==.Nihilus:BAAANQABCgEIAQAAAA==.Nikkto:BAAANQAECgUICAAAAA==.Ninfinite:BAAANQADCgYIBgAAAA==.Ninsane:BAAANQAECgMIAwAAAA==.Nintrovert:BAAANQAECgIIAgAAAA==.Nira:BAABNQAECoEaAAIHAAgKHRZkPgAnAgAHAAgKHRZkPgAnAgAAAA==.Niranrian:BAAANQADCgQIAwAAAA==.Nitroethane:BAAANQAECgYIDQAAAA==.',
No='Nodöts:BAAANQAECggICAAAAA==.Nokdis:BAAANQADCgIIAgAAAA==.Notdeadyet:BAAANQAECgQIBwAAAA==.Notron:BAAANQAECgQIDAAAAA==.Noz:BAAANQADCgYIEQAAAA==.',
Nu='Nullstorm:BAAANQADCgUIBQAAAA==.',
Ny='Nyceria:BAAANQABCgEIAwAAAA==.Nychophysis:BAAANQAECgUICwAAAA==.',
['Nø']='Nøcke:BAAANQADCggICAAAAA==.',
Oa='Oasis:BAAANQAECgEIAQAAAA==.',
Om='Omars:BAAANQAECgUICAAAAA==.',
On='Ontherun:BAAANQADCgcIDwAAAA==.',
Op='Oprawinfury:BAAANQAECgEIAQAAAA==.',
Ou='Ourus:BAABNQAECoElAAIdAAgKbSIhBAAMAwAdAAgKbSIhBAAMAwAAAA==.',
Pa='Pallaminnow:BAAANQADCggIIwAAAA==.Paulo:BAAANQAECgQJCQAAAA==.',
Pe='Pele:BAAANQAECgEIAQAAAA==.Pellito:BAAANQADCgQICAAAAA==.Perpetrator:BAAANQAECgYIDAAAAA==.',
Pi='Piki:BAAANQAECgYIDgAAAA==.',
Po='Poepwn:BAAANQAECgUIDwAAAA==.',
Pr='Prescient:BAAANQAECggIBgAAAA==.',
Pu='Puffypanda:BAAANQADCggIEgAAAA==.Putnamehere:BAAANQABCgcICQAAAA==.',
['Pû']='Pûrplehaze:BAAANQADCggICAAAAA==.',
Qu='Quill:BAAANQAECgcIEgAAAA==.',
Ra='Raging:BAAANQAECgEIAQABNQAECgUIDQABAAAAAA==.Ralz:BAAANQAECgUIEwAAAA==.Rangon:BAAANQADCggIDQAAAA==.Rannick:BAAANQAECgQICwAAAA==.Ranua:BAAANQADCgUICQABNQAECggIEgABAAAAAA==.Ratdemonmike:BAAANQAECgQICAAAAA==.Rate:BAAANQAECgQIBAABNQAECgkJHAAEABcUAA==.Ratio:BAABNQAECoEcAAIEAAkKFxQPIAARAgAEAAkKFxQPIAARAgAAAA==.Ravenhunt:BAAANQADCggIDQAAAA==.',
Re='Remi:BAAANQADCgYIBgAAAA==.Reoshe:BAAANQAECgEIAQAAAA==.',
Ri='Ripdvanwinkl:BAAANQADCgUICgAAAA==.',
Ro='Rocnimbus:BAAANQADCgEIAQAAAA==.Ronyn:BAAANQAECgUICAAAAA==.',
Ru='Ruden:BAAANQAECgMIAwAAAA==.Runed:BAAANQAECgQIBAAAAQ==.Runtimes:BAAANQAECgYIBgABNQAECggIIAAPAMseAA==.',
Rw='Rwqr:BAABNQAECoEdAAImAAYK5goFQgA/AQAmAAYK5goFQgA/AQAAAA==.',
['Rä']='Räiden:BAAANQAECgUICgAAAA==.',
Sa='Salacakei:BAAANQAECgYIEwAAAA==.Salin:BAAANQAECgUIBQAAAA==.Salithril:BAAANQADCgUIBgAAAA==.Samadams:BAAANQADCgcIEgAAAA==.Sarthy:BAACNQAFFIERAAIlAAYKqSD3AAA6AgAlAAYKqSD3AAA6AgA1AAQKgR4AAiUACQqUJYYDAGQDACUACQqUJYYDAGQDAAAA.Sassaphras:BAAANQAECgQIBAAAAA==.Satheron:BAAANQADCgEIAQAAAA==.',
Sc='Scoobie:BAAANQAECgEIAQABNQAECgYIEgABAAAAAA==.Scoobydo:BAAANQADCgIIAgABNQAECgYIEgABAAAAAA==.Scratches:BAAANQAECgIIAgAAAA==.Scrubs:BAABNQAECoEZAAIUAAgKDRY2RQBRAgAUAAgKDRY2RQBRAgAAAA==.',
Se='Septemberr:BAAANQADCgYICgAAAA==.',
Sh='Shadhunter:BAAANQABCgQIAgAAAA==.Shadpriest:BAAANQABCgIIAgABNQABCgQIAgABAAAAAA==.Shaggzy:BAACNQAFFIETAAIQAAYKmBhMAgAaAgAQAAYKmBhMAgAaAgA1AAQKgSgAAhAACQrVI4wEAHEDABAACQrVI4wEAHEDAAAA.Shamyaltak:BAAANQADCgIIAgAAAA==.Shandralore:BAAANQAECgQICwAAAA==.Shelgon:BAAANQAECgQIBQAAAA==.Shiel:BAAANQAECgQICAAAAA==.Shockdoctor:BAAANQAECgYIEwAAAA==.Shortrange:BAAANQADCgEJAQAAAA==.Shurples:BAAANQAECgEIAgABNQAECgkJKwAKACokAA==.',
Sl='Sleples:BAAANQAECgYIEgAAAA==.Slufgor:BAAANQADCggJEgAAAA==.Slyxxii:BAAANQADCgYIBgAAAA==.Slyyxxi:BAAANQADCgQIBAAAAA==.',
Sm='Smolder:BAAANQADCgcIEgAAAA==.',
Sn='Snoo:BAAANQAECgQIBwAAAA==.',
So='Solarlite:BAAANQADCggICQAAAA==.Solinari:BAAANQABCgIIAgAAAA==.Sophix:BAAANQADCgcIFwAAAA==.Sorovar:BAAANQAECgcIEwAAAA==.Soulbreakër:BAABNQAECoEXAAICAAcK6Ai8QwA3AQACAAcK6Ai8QwA3AQAAAA==.',
Sp='Spankymcbeat:BAAANQABCgYIDQAAAA==.Specimen:BAAANQADCggJEgAAAA==.Speddling:BAAANQAECgUICgAAAA==.Spiritomb:BAAANQADCgQIBAAAAA==.Spony:BAAANQADCggIIwAAAA==.Sprayanpray:BAAANQABCgIIAgAAAA==.Spuds:BAAANQAECgUIBQAAAA==.',
Sr='Srbranchmgr:BAAANQADCgEIAQAAAA==.',
St='Starbrow:BAAANQAECggIEgAAAA==.Starrybeko:BAAANQABCgYIBgABNQAECgcIEAABAAAAAA==.Stormlight:BAAANQAECgQIBgAAAA==.Strudelmaker:BAAANQAECgMIAwAAAA==.',
Su='Summernight:BAAANQADCgUIBQAAAA==.Sushistryke:BAAANQAECgEIAQAAAA==.',
Sy='Syland:BAAANQAECgQICAAAAA==.Sylvanäs:BAAANQAECgQIBAAAAA==.Syrellina:BAAANQAECgQIBAABNQAECggIEgABAAAAAA==.Sysna:BAABNQAECoEbAAMHAAcKlx85RQAKAgAHAAYK8R85RQAKAgAIAAUKbyIEIwDLAQAAAA==.',
Ta='Talirra:BAAANQABCggJBwAAAA==.Talley:BAABNQAECoEXAAIOAAYK5RNNbABvAQAOAAYK5RNNbABvAQAAAA==.Tankwar:BAAANQADCgYIFwAAAA==.Targis:BAABNQAECoEZAAIcAAgKwQvjhQC1AQAcAAgKwQvjhQC1AQAAAA==.Tauran:BAAANQADCgYIDAAAAA==.Tazanaz:BAAANQAECgUIBQABNQAECggIEgABAAAAAA==.',
Te='Templeton:BAAANQADCgMIAwABNQADCgMIAwABAAAAAA==.',
Th='Thaleas:BAAANQADCgIIAgAAAA==.Thegreatkhal:BAAANQAECgQIBgAAAA==.Thorizine:BAAANQAECgYIEAAAAA==.Thorlas:BAAANQAECgQICgAAAA==.Thotsfortots:BAAANQAECggIAwAAAA==.',
Ti='Timmúk:BAABNQAECoEbAAImAAcKZhn2KAAEAgAmAAcKZhn2KAAEAgAAAA==.',
To='Tolkorthuul:BAAANQAECgQIBQABNQADCgcICAABAAAAAA==.Tomma:BAAANQAECgcIDQAAAA==.Torment:BAAANQADCgEIAQABNQAECgUIDQABAAAAAA==.Torsion:BAAANQAECgMIBwAAAA==.',
Tr='Trailerpark:BAAANQADCgMJAwAAAA==.Tratre:BAAANQAECgUIDQAAAA==.Trevally:BAAANQADCgcIBwAAAA==.Triana:BAAANQADCggICAAAAA==.Trupeti:BAAANQAECgEIAQAAAA==.',
Tu='Tuk:BAAANQADCgUIBQAAAA==.Tumboflakes:BAAANQADCggICAABNQAFFAYIDwAmAO8aAA==.Tust:BAAANQADCggIDgABNQABCgQIAgABAAAAAA==.',
Ty='Tylandy:BAABNQAECoEbAAIXAAgKJx9cOAD6AgAXAAgKJx9cOAD6AgAAAA==.Tytaniormu:BAAANQAECgUIBgAAAA==.',
['Tê']='Tês:BAAANQAECgUICgAAAA==.',
Un='Undeadbetty:BAAANQADCgUIBQAAAA==.',
Va='Vaayl:BAAANQAECgQICwAAAA==.Vaelraen:BAAANQAECgUICgAAAA==.Valcher:BAAANQAECgEIAQAAAA==.Valendera:BAAANQAECgcIEgAAAA==.Valifadin:BAAANQAECgUICwAAAA==.Valndrevy:BAAANQADCggIEQAAAA==.Vamire:BAAANQAECggICAAAAA==.Vansan:BAAANQAECggIEgAAAA==.',
Ve='Venngennce:BAABNQAECoEiAAICAAkK3RtfFwCKAgACAAkK3RtfFwCKAgAAAA==.',
Vi='Viktir:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.Vintage:BAAANQAECgcIDAAAAA==.',
Vo='Voided:BAAANQAECgQIBgAAAA==.Vorkath:BAABNQAECoEcAAMTAAgK7CM8BAA8AwATAAgK7CM8BAA8AwAjAAMK4AtjNgCbAAAAAA==.Vormette:BAAANQADCgcIEgAAAA==.',
Vt='Vtae:BAAANQAECgMIBQAAAA==.',
Wa='Warangel:BAAANQADCgQJBAAAAA==.',
We='Werehamster:BAAANQAECgUIDgAAAA==.',
Wi='Wilbur:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
Wo='Woxkal:BAAANQAECgYIDgAAAA==.',
Wu='Wubblebubble:BAAANQAECgUICQAAAA==.',
Wy='Wyndstorm:BAAANQADCgEIAQAAAA==.',
Xa='Xaelin:BAAANQAECgQICAAAAA==.',
Xu='Xuzhu:BAAANQAECgYICwABNQAECgkJGQANAHoaAA==.',
Yi='Yinei:BAAANQADCgEIAQAAAA==.',
Yl='Ylvis:BAAANQAECgYIEAAAAA==.',
Yo='Yol:BAABNQAECoEZAAIiAAgKkQ9VCACzAQAiAAgKkQ9VCACzAQAAAA==.Yoliesha:BAAANQABCgYIBwAAAA==.Yoshymi:BAAANQAECgYIEgAAAQ==.',
Yv='Yvetal:BAAANQAECgMIBAABNQAECgkJGAAYAF8UAA==.',
Za='Zarion:BAABNQAECoEiAAMMAAkKTyPqAgCGAwAMAAkKTyPqAgCGAwANAAEK2wVioAAfAAAAAA==.Zarra:BAAANQAECgIJBAAAAA==.',
Ze='Zerofoxtogiv:BAAANQAECgQJBAAAAA==.',
Zf='Zf:BAAANQABCgQIBAAAAA==.',
Zi='Zilik:BAAANQADCgUIBQABNQAECgkJIgAMAE8jAA==.Ziyar:BAAANQAECgMIBAABNQAECgkJIgAMAE8jAA==.',
Zo='Zocorro:BAAANQADCggIFgAAAA==.',
Zy='Zypherdius:BAAANQADCgYIDwAAAA==.Zytheline:BAAANQADCgIIAgAAAA==.',
['Ðe']='Ðecision:BAACNQAFFIEPAAIaAAQKXQ6aCgAsAQAaAAQKXQ6aCgAsAQA1AAQKgSQAAhoACQrbIVIgABIDABoACQrbIVIgABIDAAAA.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
