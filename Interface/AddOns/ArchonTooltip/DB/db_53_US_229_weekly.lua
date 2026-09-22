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

local lookup = {'DemonHunter-Devourer','Shaman-Elemental','Rogue-Outlaw','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Monk-Windwalker','Rogue-Assassination','Evoker-Devastation','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Shaman-Enhancement','Mage-Arcane','Unknown-Unknown','Paladin-Retribution','Paladin-Holy','Hunter-Marksmanship','Mage-Frost','Rogue-Subtlety','Warlock-Affliction','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Warrior-Protection','DemonHunter-Havoc','DeathKnight-Frost','Druid-Restoration','Druid-Balance',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaralyn:BAAANQAECgEIAQAAAA==.',
Ab='Abmikaze:BAAANQADCggICgAAAA==.Abysseon:BAAANQAECgcJDwAAAA==.',
Ac='Ace:BAAANQAECgQICAAAAA==.',
Ad='Adios:BAACNQAFFIELAAIBAAQKAguCBQBFAQABAAQKAguCBQBFAQA1AAQKgR0AAgEACQpvHMsMAOYCAAEACQpvHMsMAOYCAAAA.Adorean:BAAANQAECgUICwAAAA==.',
Ae='Aenymbria:BAAANQADCgMJAwAAAA==.',
Ag='Age:BAAANQAECgQIBgAAAA==.Agrohn:BAAANQAECgQIBAAAAA==.',
Ai='Aimnskin:BAAANQADCggJEwAAAA==.',
Al='Alcore:BAAANQAECgQJBQAAAA==.Aliine:BAAANQAECgQJCgAAAA==.',
Am='Ameiisaa:BAAANQAECgIIAgAAAA==.Amethaendron:BAAANQADCgcIDgAAAA==.Amneesia:BAAANQADCgQIBQAAAA==.Amytiel:BAABNQAECoElAAICAAkKHx3lFgD1AgACAAkKHx3lFgD1AgAAAA==.',
An='Anxie:BAAANQAECgcJBwAAAA==.Anìtamaxwynn:BAAANQADCgQIBAABNQAFFAUICwADAL8ZAA==.',
Ao='Aoifae:BAAANQAECgIIAwAAAA==.',
Ap='Apickle:BAAANQADCggIDQAAAA==.Applecider:BAABNQAECoEXAAQEAAgKvwfDXgBdAQAEAAcKCwjDXgBdAQAFAAcKdgcLKQBcAQAGAAEKMAUWIAApAAAAAA==.Apprentice:BAAANQAECgQJBQAAAA==.',
Ar='Aramos:BAAANQAECgYJEAAAAA==.Aramôs:BAAANQADCggIGwAAAA==.Arkhangel:BAAANQAECgQJCQAAAA==.Arta:BAAANQADCggIIAAAAA==.',
As='Asgnomeus:BAAANQADCgUIBQAAAA==.Ashhealz:BAAANQAECgIIBQAAAA==.',
At='Atraxx:BAAANQABCgMIBAAAAA==.',
Ax='Axlegrease:BAAANQADCgcIEgAAAA==.',
Az='Azuzu:BAAANQAECgEIAQABNQAECggJGQAHANkPAA==.',
Ba='Balacarn:BAAANQAECgIIAwAAAA==.Barlok:BAAANQAECgIIAgAAAA==.',
Be='Beaker:BAAANQAECgcJDgAAAA==.Beastmode:BAAANQAECgcIEgAAAA==.Bedlem:BAAANQAECgQJBAAAAA==.Beko:BAAANQAECgUICQAAAA==.Belonna:BAAANQABCgEIAQAAAA==.Bendytwotime:BAAANQABCgIIAgAAAA==.',
Bi='Bidoof:BAAANQAECgMJBAAAAA==.Billydan:BAAANQAECgUICgAAAA==.',
Bl='Blackhide:BAAANQABCgMIBAAAAA==.Blackpanthxr:BAAANQAECgcJEwAAAA==.Blackvortex:BAAANQADCgIIAgAAAA==.Bloodsoul:BAAANQAECgMIBQAAAA==.Bloodybloodz:BAAANQADCggICAABNQAECggIFwAIAFEjAA==.Bloodyburst:BAABNQAECoEVAAMDAAgKbyCCAwCxAgADAAcKZSKCAwCxAgAJAAEKuBKfWgBFAAABNQAECggIFwAIAFEjAA==.Bloodyfistz:BAABNQAECoEXAAIIAAgKUSMpBwAhAwAIAAgKUSMpBwAhAwAAAA==.Blue:BAAANQAECgYIDwAAAA==.Bluethreetwo:BAAANQAECgQIBgAAAA==.',
Bo='Bookofzeref:BAAANQADCgEIAQAAAA==.',
Br='Brayend:BAAANQAECgYJCQAAAA==.Brimscythe:BAABNQAECoEYAAIKAAcKoxH3EgDBAQAKAAcKoxH3EgDBAQAAAA==.Brutalx:BAAANQADCggICAAAAA==.',
By='Byebyeman:BAAANQADCgYIBgAAAA==.',
Ca='Calaveras:BAAANQABCggJCgAAAA==.Caliandis:BAAANQAECgQJBgAAAA==.Calvey:BAAANQAECgMIAwAAAA==.Cambrai:BAAANQAECgIJAgAAAA==.Cannabelle:BAABNQAECoEXAAILAAcKCSXzFAD9AgALAAcKCSXzFAD9AgAAAA==.Carclias:BAABNQAECoEiAAMMAAkKNRZPCQBHAgAMAAgKCxZPCQBHAgANAAcKABP9UgDVAQAAAA==.Carthrix:BAAANQAECgYIBgAAAA==.Catbarf:BAAANQADCggIBgABNQAECggJGQAOAIMeAA==.Cathrix:BAAANQADCgIIAgAAAA==.Cattlerage:BAAANQAECgQIBgAAAA==.',
Ce='Cellika:BAAANQAECgMJBAAAAA==.Cerdelz:BAAANQAECgMIAwAAAA==.',
Ch='Chaoscookies:BAAANQAECgYJEgAAAA==.Chartkov:BAAANQADCggIDQAAAA==.Cheeseballer:BAAANQAECgIIAgAAAA==.Chermer:BAAANQADCgQIBAAAAA==.Chubbytoyboy:BAAANQADCgYIBgABNQAECggIGgAPAJEPAA==.',
Ci='Cinderpetal:BAAANQAECgEJAQAAAA==.',
Ck='Ckay:BAAANQADCggJCAAAAA==.',
Co='Cobrakaidojo:BAAANQAECgYIBwAAAA==.Cohemew:BAAANQAECggIEgABNQAECgkJHwANANUeAA==.Comlock:BAAANQADCgYIDAAAAA==.Complacent:BAAANQAECgUICQAAAA==.Comrage:BAAANQABCgQIAgAAAA==.Comspyder:BAAANQAECgEJAQAAAA==.Coriander:BAAANQAECgYJEQAAAA==.Corii:BAAANQADCgMJAwAAAA==.Cosmo:BAAANQAECgEIAQABNQAECgMIBQAQAAAAAA==.',
Ct='Cthùlhù:BAAANQADCggICAAAAA==.',
Cu='Cursedchild:BAAANQAECggIDAABNQAFFAYIDgAIAHAVAA==.',
Cy='Cyonicus:BAAANQAECgUJCwAAAA==.Cyska:BAABNQAECoEZAAIHAAgK2Q82OQCwAQAHAAgK2Q82OQCwAQAAAA==.',
['Cé']='Cécé:BAAANQAECgUICgAAAA==.',
['Cë']='Cëcë:BAAANQADCgMIBgAAAA==.',
Da='Dababayaga:BAAANQAECgEJAQAAAA==.Dagaroonie:BAAANQAECgMIAwAAAA==.Dagerlaurn:BAAANQAECgYIDAAAAA==.Dagevas:BAAANQADCgYIBgAAAA==.Dakeria:BAAANQADCgYIDwAAAA==.Darkando:BAAANQADCgcIDQAAAA==.Darksoldier:BAAANQAECgYJDwAAAA==.Darthfire:BAAANQABCgYICAAAAA==.Dartoy:BAEANQAECgYJDwABNQAFFAMIBQARANYZAA==.Dax:BAAANQAECgEJAgAAAA==.Daxing:BAAANQADCggIFAABNQAECgcJDQAQAAAAAA==.',
De='Deeppurple:BAAANQADCgcJCQAAAA==.Del:BAAANQAECgcJEQAAAA==.Demoniaca:BAAANQADCgEIAQAAAA==.Demonic:BAAANQAECgEIAQABNQAECgQICAAQAAAAAA==.Demoraliziñg:BAAANQADCggIDgAAAA==.Demostache:BAABNQAECoEfAAMNAAkK1R5FHwCuAgANAAgK8B1FHwCuAgAMAAEKACY5TwBuAAAAAA==.Derevi:BAAANQADCgcIBwAAAA==.Despot:BAAANQAECgIJAwAAAA==.',
Dh='Dhargal:BAAANQAECgYJEAAAAA==.',
Dk='Dkfaros:BAAANQADCgYICwABNQAECgUIDAAQAAAAAA==.',
Do='Dolomite:BAAANQAECgYJCwAAAA==.Dorow:BAAANQAECgcIEAABNQAFFAEIAQAQAAAAAA==.Dotabolt:BAAANQAECgQJCwAAAA==.',
Dr='Dracthyris:BAAANQADCggICwAAAA==.Dragonash:BAAANQADCgYIBgAAAA==.Draéne:BAAANQADCgcIEAAAAA==.Dreaa:BAAANQADCgEIAQAAAA==.Drinkme:BAAANQADCgEIAQAAAA==.Droki:BAABNQAECoEZAAIOAAgKgx47BgDgAgAOAAgKgx47BgDgAgAAAA==.',
Du='Dunsel:BAAANQAECgMJAwABNQAECgcIGAAKAKMRAA==.Dunwich:BAAANQADCgIIAgAAAA==.Duulket:BAAANQAECgMJAwAAAA==.',
Dy='Dyanna:BAAANQABCgYICgAAAA==.',
['Dà']='Dànny:BAAANQAECgYJDwAAAA==.',
['Dã']='Dãnny:BAAANQADCgEIAQABNQAECgYJDwAQAAAAAA==.',
Eb='Ebonshade:BAAANQADCgcIEAAAAA==.',
Ed='Edena:BAAANQADCgEIAQAAAA==.Edginglord:BAAANQAECgIJAgAAAA==.Edya:BAAANQADCgIIAgAAAA==.',
El='Elgringo:BAAANQADCgEIAQABNQADCgUIBQAQAAAAAA==.Eloras:BAAANQAECgEJAQAAAA==.Elunbi:BAABNQAECoEeAAMGAAgKoRf4CABwAQAEAAgK7BaTNgAVAgAGAAYKkhT4CABwAQAAAA==.',
Em='Emovoker:BAAANQADCgYIBAAAAA==.Emshady:BAAANQADCgEIAQAAAA==.',
Ep='Epsilòn:BAEANQAECggIEAAAAA==.',
Er='Ernest:BAAANQADCggJHgAAAA==.Errani:BAAANQAECgQIBwAAAA==.',
Es='Esper:BAAANQAECgYJBwAAAA==.',
Eu='Eureki:BAAANQAECgQIBQAAAA==.',
Ev='Evilkarma:BAAANQAECgQJBAAAAA==.Evocatis:BAABNQAECoEZAAMRAAkKbyNXDwBaAwARAAkKbyNXDwBaAwASAAIKEQdouwBvAAAAAA==.',
Ey='Eyekonicklok:BAAANQADCgYJBgAAAA==.Eyesdeadeyed:BAABNQAECoEbAAITAAgKqRFFHgD6AQATAAgKqRFFHgD6AQAAAA==.',
Fa='Faion:BAAANQAECgYJCwAAAA==.Faon:BAAANQADCgEIAQAAAA==.Farrea:BAAANQADCggIDQAAAA==.Fayvia:BAAANQABCggIDQAAAA==.',
Fe='Feebz:BAAANQADCgEIAQAAAA==.Felzbirt:BAAANQAECgEIAQAAAA==.Feorely:BAAANQAECgcIEgAAAA==.',
Fi='Firebirdz:BAAANQAFFAEJAQAAAA==.',
Fl='Flygon:BAAANQAECgEIAQAAAA==.',
Fo='Forque:BAAANQADCgYICAAAAA==.',
Fr='Frater:BAAANQADCgEIAQAAAA==.Frequentine:BAAANQAECgUIDQAAAA==.Frizby:BAAANQAECgEIAQAAAA==.Frostypaw:BAAANQADCgIIAgAAAA==.',
Fu='Fuzzybut:BAAANQAECgIIBAAAAA==.',
Fy='Fyrelord:BAAANQADCggJIAAAAA==.Fyuna:BAAANQAECgcJEQAAAA==.',
Ga='Gark:BAAANQADCggJEwAAAA==.Garkk:BAAANQADCgQJBAAAAA==.Gazzi:BAAANQAECgYJEQAAAA==.',
Ge='Genevieve:BAAANQAECgEIAQABNQAECgQJBgAQAAAAAA==.',
Gi='Gióvanna:BAAANQADCgcJCgAAAA==.',
Gl='Glodskegg:BAAANQAECgYJEQAAAA==.',
Go='Goldensea:BAAANQAECgMIBAAAAA==.Gotenk:BAAANQAECgQJBAAAAA==.Goyim:BAAANQAECgEIAQAAAA==.',
Gr='Gr:BAAANQADCgMIBwAAAA==.Grissoul:BAAANQABCgQIBAAAAA==.Grody:BAAANQAECgQJBgAAAA==.',
Gu='Guroo:BAAANQAECgYJEAAAAA==.',
['Gá']='Gárp:BAAANQAECgEIAQAAAA==.',
Ha='Hagarn:BAABNQAECoEZAAIRAAgKGBB+WwDtAQARAAgKGBB+WwDtAQAAAA==.Halimah:BAAANQAECgQJCQAAAA==.Halois:BAAANQADCgYIBgABNQAECgYJEAAQAAAAAA==.Hardtwosee:BAAANQAECggIDQABNQAECgkJGwASAE8eAA==.Harleypaw:BAAANQAECggICAAAAA==.Hazan:BAAANQAECgYIBgABNQAECggJGQAOAIMeAA==.',
He='Hexmachine:BAAANQAECgcIEwAAAA==.',
Ho='Hole:BAAANQADCgYJBgAAAA==.Holyflem:BAAANQADCggICAAAAA==.',
Hu='Huntzcatzup:BAAANQADCgYICwAAAA==.',
Hy='Hypertext:BAAANQAECgQIAgAAAA==.',
Ia='Iamahriman:BAAANQAECgYJCQAAAA==.Iamarawn:BAAANQAECgQIBAAAAA==.',
Ig='Ignite:BAAANQAECgYIDwAAAA==.',
Il='Illestria:BAAANQAECgYJDwAAAA==.Illumiscotty:BAABNQAECoEZAAMPAAgK0iE2NwDnAgAPAAgK0iE2NwDnAgAUAAEKzBhYKgBGAAAAAA==.',
In='Incognonetoo:BAAANQAECgYJCAAAAA==.Insania:BAAANQAECgQJBQAAAA==.',
Ir='Ironhands:BAAANQADCgYIBgAAAA==.',
Iz='Izara:BAAANQADCgUIEAAAAA==.',
Ja='Jamizi:BAAANQADCgcIBwAAAA==.Jaspally:BAAANQADCggJDgABNQAECgcJDQAQAAAAAA==.Jastirri:BAAANQAECgUJBwAAAA==.',
Ji='Jimbojonesjr:BAAANQAECgIIAgAAAA==.Jimothy:BAAANQADCgYIBgABNQABCgQIAgAQAAAAAA==.',
Jo='Johneringo:BAAANQAECgEJAQAAAA==.Jonjee:BAAANQAECgYIEQAAAA==.',
Ju='Juicez:BAAANQADCggIFgAAAA==.Jurkee:BAAANQADCgYICwAAAA==.',
Ka='Kahekili:BAAANQADCgYICgAAAA==.Kain:BAAANQAECgcJBAAAAA==.Kalak:BAAANQABCgIIAgAAAA==.Kaleielin:BAAANQAECggIDAAAAA==.Katio:BAABNQAECoEYAAMJAAgKVByyKQCKAQAJAAQKECCyKQCKAQAVAAQKmRjsJwAvAQAAAA==.Kayanna:BAAANQADCgQIBAAAAA==.Kayhless:BAAANQAECgQJBAAAAA==.Kazunt:BAAANQABCgQIBAAAAA==.',
Ke='Kershneep:BAAANQADCggJFwAAAA==.Kessandra:BAACNQAFFIELAAMNAAUK5R0fAwC+AQANAAUKUxwfAwC+AQAWAAEK8CJRAwBkAAA1AAQKgRsAAxYACQpGJMAAAE0DABYACQr7IsAAAE0DAA0ABQpSGrpwAHEBAAAA.Kexally:BAAANQADCggIGgAAAA==.Kexkan:BAAANQADCgQICAABNQADCggIGgAQAAAAAA==.Kezzia:BAAANQADCgMIAwAAAA==.',
Kh='Khurri:BAAANQAECgYJEQAAAA==.',
Ki='Kiarah:BAAANQAECgIIBAAAAA==.Killplz:BAAANQADCgYIFQAAAA==.Kirr:BAAANQAECgUIBwAAAA==.Kisor:BAAANQADCgEIAQAAAA==.Kitchenstink:BAAANQAECgYIEQAAAA==.',
Ko='Koifo:BAAANQABCgQIBAAAAA==.',
Kp='Kplaow:BAAANQABCggICgAAAA==.',
Kr='Kritanta:BAAANQAECgYJEAAAAA==.Krystallus:BAAANQADCgYICwAAAA==.',
Ku='Kurnea:BAAANQAECgIJAgAAAA==.',
['Kó']='Kórrá:BAAANQADCgMIAwAAAA==.',
La='Lachlann:BAAANQAECgMJAwAAAA==.Lakartó:BAABNQAECoEhAAQKAAgKqxyyCwBiAgAKAAgKmRmyCwBiAgAXAAUK3BoaCACMAQAYAAEKWB/rNQBYAAAAAA==.Laura:BAAANQABCgEIAQAAAA==.Law:BAAANQAECgMIAwAAAA==.',
Ld='Ldritch:BAABNQAECoEdAAMVAAkKJSQTEQA5AgAVAAYKgSMTEQA5AgAJAAUKuSO5HAD+AQAAAA==.',
Le='Leifson:BAAANQAECgMJBQAAAA==.Leonedis:BAAANQAECgQJBQAAAA==.Lethea:BAAANQADCgYICQAAAA==.Levious:BAAANQAECgUJCAAAAA==.',
Li='Lianara:BAAANQADCgQJCAABNQADCggJEwAQAAAAAA==.Lidorisse:BAAANQADCgYIBgAAAA==.',
Lo='Lovedoctor:BAAANQABCgUIBQAAAA==.',
Lu='Ludo:BAABNQAECoEeAAIOAAkKIiBVAwBBAwAOAAkKIiBVAwBBAwAAAA==.Lukri:BAAANQADCgcICAAAAA==.Lumisbrew:BAAANQAECgcJEQAAAA==.Luxurious:BAAANQAECgQIBgAAAA==.',
Ma='Maaca:BAAANQADCgYICgAAAA==.Malachor:BAAANQADCgQIBAABNQADCggJEgAQAAAAAA==.Maligned:BAAANQAECgEIAQAAAA==.Martichoux:BAAANQAECgYJEQAAAA==.Match:BAAANQAECgMJAwAAAA==.Mathas:BAABNQAECoEaAAQSAAgKjxmHOQASAgASAAcKiBiHOQASAgARAAIKeAdi/gBdAAAZAAEKpw7aTAAsAAAAAA==.Mathilda:BAAANQAECgIJAgAAAA==.',
Mc='Mccholock:BAAANQAECgIIBgAAAA==.Mcmach:BAAANQAECgIIAgAAAA==.',
Me='Meddox:BAAANQABCggIDAAAAA==.Mehaoloka:BAAANQADCgcICgAAAA==.Memelle:BAAANQAECgQJBgAAAA==.Menoah:BAAANQAECgQJBwAAAA==.Menotthatorc:BAAANQADCgIIAgABNQAECgkJHwANANUeAA==.Merdoc:BAAANQAECgQJBAAAAA==.Meredith:BAAANQAECgQJBgAAAA==.Mesilana:BAAANQADCggIDAAAAA==.Metrx:BAAANQADCgUIBQAAAA==.',
Mi='Miltank:BAAANQADCgYIDAAAAA==.Mirenna:BAAANQAECgQJBgAAAA==.Misseymiss:BAAANQADCgIIAgAAAA==.Mithian:BAAANQADCgMJAwAAAA==.',
Mo='Mogwhy:BAAANQADCgYIBgAAAA==.Molbeato:BAAANQAECgIIAgAAAA==.Monichan:BAAANQADCgcJCAAAAA==.Moosecheeks:BAAANQAECgYICwAAAA==.Morganna:BAAANQABCggIDQAAAA==.Morior:BAAANQAECgQJBAAAAA==.Morslucifer:BAAANQAECgYJDwAAAA==.Motorcade:BAAANQAECgQJBQAAAA==.',
Mu='Mutent:BAAANQADCgYIDAAAAA==.',
My='Mypal:BAAANQADCggJIwAAAA==.Myrelis:BAAANQAFFAEIAQAAAA==.',
Na='Naula:BAAANQADCgcIDgAAAA==.',
Ne='Neather:BAAANQAECgIIAgAAAA==.Neron:BAAANQADCgQIBAAAAA==.Nezkima:BAAANQADCgQJBAAAAA==.',
Ni='Nihilus:BAAANQABCgEIAQAAAA==.Nikkto:BAAANQAECgMJAwAAAA==.Ninfinite:BAAANQADCgYIBgAAAA==.Ninsane:BAAANQAECgMIAwAAAA==.Nintrovert:BAAANQAECgIIAgAAAA==.Nira:BAAANQAECgcJDwAAAA==.Niranrian:BAAANQADCgQIAwAAAA==.Nitroethane:BAAANQAECgUJCwAAAA==.',
No='Nodöts:BAAANQAECggICAABNQAECgkJGwASAE8eAA==.Nokdis:BAAANQADCgIIAgAAAA==.Notdeadyet:BAAANQAECgIIAwAAAA==.Notron:BAAANQAECgQJCgAAAA==.Noz:BAAANQADCgYIDgAAAA==.',
Nu='Nullstorm:BAAANQADCgUIBQAAAA==.',
Ny='Nyceria:BAAANQABCgEIAwAAAA==.Nychophysis:BAAANQAECgQIBgAAAA==.',
['Nø']='Nøcke:BAAANQADCggICAAAAA==.',
Om='Omars:BAAANQAECgMIAwAAAA==.',
On='Ontherun:BAAANQADCgYIDQAAAA==.',
Op='Oprawinfury:BAAANQADCggJEwAAAA==.',
Ou='Ourus:BAABNQAECoEdAAIaAAgK+h9cBADcAgAaAAgK+h9cBADcAgAAAA==.',
Pa='Pallaminnow:BAAANQADCggIIwAAAA==.Paulo:BAAANQAECgQJCQAAAA==.',
Pe='Pele:BAAANQADCggJEwAAAA==.Pellito:BAAANQADCgQJBAAAAA==.Perpetrator:BAAANQAECgQIBgAAAA==.',
Pi='Piki:BAAANQAECgQJCAAAAA==.',
Po='Poepwn:BAAANQAECgUICgAAAA==.',
Pu='Puffypanda:BAAANQADCggJDwAAAA==.',
Qu='Quill:BAAANQAECgYJEQAAAA==.',
Ra='Raging:BAAANQADCgUIBQABNQAECgQICAAQAAAAAA==.Ralz:BAAANQAECgUJEwAAAA==.Rangon:BAAANQADCggICAAAAA==.Rannick:BAAANQAECgQJBwAAAA==.Ranua:BAAANQADCgUICQABNQAECgcJDQAQAAAAAA==.Ratdemonmike:BAAANQAECgIIBAAAAA==.Ratio:BAAANQAECggJEQAAAA==.Ravenhunt:BAAANQADCggIDQAAAA==.',
Re='Remi:BAAANQADCgYIBgAAAA==.',
Ri='Ripdvanwinkl:BAAANQADCgUICgAAAA==.',
Ro='Rocnimbus:BAAANQADCgEIAQAAAA==.Ronyn:BAAANQAECgMIAwAAAA==.',
Ru='Ruden:BAAANQADCggJEgAAAA==.Runed:BAAANQAECgQIBAAAAQ==.Runtimes:BAAANQAECgYIBgABNQAECggJGQAOAIMeAA==.',
Rw='Rwqr:BAABNQAECoEZAAIbAAYK6QlrNwBCAQAbAAYK6QlrNwBCAQAAAA==.',
['Rä']='Räiden:BAAANQAECgUJBQAAAA==.',
Sa='Salacakei:BAAANQAECgUJDQAAAA==.Salin:BAAANQAECgQIBAAAAA==.Salithril:BAAANQADCgUIBgAAAA==.Samadams:BAAANQADCgcIEgAAAA==.Sarthy:BAACNQAFFIELAAIZAAUK1CEpAQDqAQAZAAUK1CEpAQDqAQA1AAQKgRwAAhkACQqLJS4CAI8DABkACQqLJS4CAI8DAAAA.Sassaphras:BAAANQAECgQIBAAAAA==.Satheron:BAAANQADCgEIAQAAAA==.',
Sc='Scoobie:BAAANQADCgQJBQABNQAECgUIDAAQAAAAAA==.Scoobydo:BAAANQABCgIIAgABNQAECgUIDAAQAAAAAA==.Scratches:BAAANQABCgIIAgAAAA==.Scrubs:BAAANQAFFAEJAQAAAA==.',
Se='Septemberr:BAAANQADCgQIBAAAAA==.',
Sh='Shadhunter:BAAANQABCgQJAgAAAA==.Shadpriest:BAAANQABCgIIAgABNQABCgQJAgAQAAAAAA==.Shaggzy:BAACNQAFFIEOAAIIAAYKcBXMAQADAgAIAAYKcBXMAQADAgA1AAQKgSYAAggACQqjIwcDAIwDAAgACQqjIwcDAIwDAAAA.Shamyaltak:BAAANQADCgIIAgAAAA==.Shandralore:BAAANQAECgQJBwAAAA==.Shelgon:BAAANQAECgQIBQAAAA==.Shiel:BAAANQAECgIIBAAAAA==.Shockdoctor:BAAANQAECgYJDQAAAA==.Shortrange:BAAANQADCgEJAQAAAA==.Shurples:BAAANQAECgEIAgABNQAECgkJJQASAPwjAA==.',
Sl='Sleples:BAAANQAECgUIDAAAAA==.Slufgor:BAAANQADCggJEgAAAA==.Slyxxii:BAAANQADCgYIBgAAAA==.Slyyxxi:BAAANQADCgQIBAAAAA==.',
Sm='Smolder:BAAANQADCgYICwAAAA==.',
Sn='Snoo:BAAANQAECgIIAwAAAA==.',
So='Solarlite:BAAANQADCgEIAQAAAA==.Solinari:BAAANQABCgIIAgAAAA==.Sophix:BAAANQADCgcIEAAAAA==.Sorovar:BAAANQAECgYIEQAAAA==.Soulbreakër:BAAANQAECgUIDgAAAA==.',
Sp='Spankymcbeat:BAAANQABCgYJDQAAAA==.Specimen:BAAANQADCggJEgAAAA==.Speddling:BAAANQAECgMIBQAAAA==.Spiritomb:BAAANQADCgQIBAAAAA==.Spony:BAAANQADCgcIGwAAAA==.Sprayanpray:BAAANQABCgIIAgAAAA==.Spuds:BAAANQADCgMJAwAAAA==.',
St='Starbrow:BAAANQAECgUIDAAAAA==.Stormlight:BAAANQAECgIJAgAAAA==.Strudelmaker:BAAANQAECgMJAgAAAA==.',
Su='Summernight:BAAANQADCgUIBQAAAA==.Sushistryke:BAAANQADCggIGgAAAA==.',
Sy='Syland:BAAANQAECgIIBAAAAA==.Sylvanäs:BAAANQADCgcJDwAAAA==.Sysna:BAAANQAECgYJEwAAAA==.',
Ta='Talirra:BAAANQABCggJBwAAAA==.Talley:BAAANQAECgYJEQAAAA==.Tankwar:BAAANQADCgUJEQAAAA==.Targis:BAAANQAECgcIEAAAAA==.Tauran:BAAANQADCgUIBQAAAA==.Tazanaz:BAAANQAECgUIBQABNQAECgcJDQAQAAAAAA==.',
Te='Templeton:BAAANQADCgMIAwAAAA==.',
Th='Thaleas:BAAANQADCgEIAQAAAA==.Thegreatkhal:BAAANQAECgIJAgAAAA==.Thorizine:BAAANQAECgYJEAAAAA==.Thorlas:BAAANQAECgIIBgAAAA==.',
Ti='Timmúk:BAABNQAECoEYAAIbAAYKNhopJwDVAQAbAAYKNhopJwDVAQAAAA==.',
To='Tolkorthuul:BAAANQAECgQIBQABNQADCgcICAAQAAAAAA==.Tomma:BAAANQAECgYICwAAAA==.Torsion:BAAANQAECgIIAgAAAA==.',
Tr='Trailerpark:BAAANQADCgMJAwAAAA==.Tratre:BAAANQAECgUICAAAAA==.Trevally:BAAANQADCgcIBwAAAA==.Triana:BAAANQADCggICAAAAA==.Trupeti:BAAANQADCggIHwAAAA==.',
Tu='Tuk:BAAANQADCgUIBQAAAA==.Tumboflakes:BAAANQADCggICAABNQAFFAUJCwAbAN8aAA==.Tust:BAAANQADCggIDgABNQABCgQIAgAQAAAAAA==.',
Ty='Tylandy:BAAANQAECgYJDQAAAA==.Tytaniormu:BAAANQAECgQIBQAAAA==.',
['Tê']='Tês:BAAANQAECgIIBQAAAA==.',
Un='Undeadbetty:BAAANQADCgUIBQAAAA==.',
Va='Vaayl:BAAANQAECgQJBwAAAA==.Vaelraen:BAAANQAECgQJBQAAAA==.Valcher:BAAANQAECgEJAQAAAA==.Valendera:BAAANQAECgYJEQAAAA==.Valifadin:BAAANQAECgQJBgAAAA==.Valndrevy:BAAANQADCgcIDwAAAA==.Vansan:BAAANQAECgcJDQAAAA==.',
Ve='Venngennce:BAABNQAECoEaAAIcAAgKGxogGgA0AgAcAAgKGxogGgA0AgAAAA==.',
Vi='Viktir:BAAANQADCgQJBAABNQADCggJEwAQAAAAAA==.Vintage:BAAANQAECgcIDAAAAA==.',
Vo='Voided:BAAANQAECgQIBgAAAA==.Vorkath:BAAANQAECgcJEQAAAA==.Vormette:BAAANQADCgYICwAAAA==.',
Vt='Vtae:BAAANQAECgIJAgAAAA==.',
Wa='Warangel:BAAANQADCgQJBAAAAA==.',
We='Werehamster:BAAANQAECgQICQAAAA==.',
Wo='Woxkal:BAAANQAECgUJCAAAAA==.',
Wu='Wubblebubble:BAAANQAECgUICQAAAA==.',
Wy='Wyndstorm:BAAANQADCgEIAQAAAA==.',
Xa='Xaelin:BAAANQAECgIIBAAAAA==.',
Xu='Xuzhu:BAAANQAECgQIBwAAAA==.',
Yl='Ylvis:BAAANQAECgUICgAAAA==.',
Yo='Yol:BAABNQAECoEXAAIXAAgKdA79BgC7AQAXAAgKdA79BgC7AQAAAA==.Yoliesha:BAAANQABCgYJBwAAAA==.Yoshymi:BAAANQAECgUIDAAAAQ==.',
Yv='Yvetal:BAAANQADCgMIAwABNQAECgkJHwANANUeAA==.',
Za='Zarion:BAABNQAECoEfAAMdAAkKTyPpAQCTAwAdAAkKTyPpAQCTAwAeAAEK2wWIjQAjAAAAAA==.Zarra:BAAANQAECgIJBAAAAA==.',
Ze='Zerofoxtogiv:BAAANQAECgQJBAAAAA==.',
Zf='Zf:BAAANQABCgQIBAAAAA==.',
Zi='Zilik:BAAANQADCgUIBQABNQAECgkJHwAdAE8jAA==.Ziyar:BAAANQAECgEIAgABNQAECgkJHwAdAE8jAA==.',
Zo='Zocorro:BAAANQADCggJEwAAAA==.',
Zy='Zypherdius:BAAANQADCgYICQAAAA==.Zytheline:BAAANQADCgIIAgAAAA==.',
['Ðe']='Ðecision:BAACNQAFFIELAAIRAAQKrw2fBgAwAQARAAQKrw2fBgAwAQA1AAQKgSAAAhEACQrbIeAUADEDABEACQrbIeAUADEDAAAA.',
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
