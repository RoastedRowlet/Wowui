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

local lookup = {'Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Druid-Balance','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Evoker-Preservation','Druid-Guardian','Priest-Discipline','Paladin-Holy','Paladin-Retribution','Mage-Fire','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Protection','Mage-Frost','DemonHunter-Havoc','Unknown-Unknown','Druid-Restoration','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Monk-Mistweaver','Shaman-Elemental','Warrior-Arms','DemonHunter-Vengeance','Warrior-Protection','Shaman-Enhancement','Druid-Feral','Hunter-Survival',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=46,date='2026-08-11',data={Ab='Abbaddon:BAAALgADCgcJBwAAAA==.Aberration:BAAALgADCgMJAwAAAA==.Absolutezero:BAAALgADCggJFAAAAA==.',
Ad='Addison:BAAALgAECgQJBQAAAA==.Adicia:BAAALgAECgMJAwAAAA==.Adormi:BAAALgAECgQJBQAAAA==.',
Ae='Aestel:BAAALgADCgEJAQAAAA==.',
Ai='Aidum:BAAALgADCgMJAwAAAA==.',
Al='Alarus:BAAALgADCgYJCAAAAA==.Algrumm:BAAALgAECgQJBQAAAA==.Allesar:BAABLgAECn8cAAIBAAcJtxzGAgA5AgABAAcJtxzGAgA5AgAAAA==.Allila:BAABLgAECn8eAAICAAgJghwpFgAaAgACAAgJghwpFgAaAgAAAA==.Aloreith:BAAALgAECgEJAQAAAA==.Aloysia:BAAALgADCgUJCAAAAA==.',
Am='Ambrozyn:BAAALgAECgkJDwAAAA==.',
An='Andrew:BAAALgAECgYJCgAAAA==.Anik:BAAALgAECgYJBwAAAA==.Animalz:BAAALgADCgYJBgABLgAECgkJFgADAKoQAA==.Anna:BAABLgAFFH8LAAICAAUJPBwpEwBNAQACAAUJPBwpEwBNAQAAAA==.Anturoc:BAAALgADCgkJFwAAAA==.',
Ap='Apalrapzz:BAABLgAECn8XAAICAAYJtQOEXwCaAAACAAYJtQOEXwCaAAABLgAECgkJQwAEAG8GAA==.Apollo:BAAALgADCgEJAQAAAA==.',
Ar='Araphael:BAAALgAECgYJBwAAAA==.Ardrelar:BAABLgAECn8YAAIFAAgJdAswOwBZAQAFAAgJdAswOwBZAQAAAA==.Arekanna:BAAALgAECgMJAwAAAA==.Arieljoyeria:BAACLgAFFH8RAAMGAAYJSBwEBABPAQAGAAQJ4B4EBABPAQAHAAQJoRsuGgCuAAAuAAQKfyQAAwcACQmZH+MNAMACAAcACQkfHuMNAMACAAYABAkqGOIRAAcBAAAA.Aroseath:BAAALgADCgMJAwAAAA==.Arthoz:BAAALgADCgIJAgABLgAECggJGQAIAP4RAA==.',
As='Ashog:BAAALgAECgIJAgAAAA==.Astar:BAAALgAECgEJAQABLgAFFAQJDwAJADAcAA==.Astraea:BAABLgAECn9dAAIKAAkJMiDhAADZAgAKAAkJMiDhAADZAgABLgAECgkJVgAIACEjAA==.',
At='Athika:BAAALgAECgEJAQAAAA==.',
Au='Auddorn:BAAALgAECgYJDAAAAA==.Auria:BAABLgAECn8dAAILAAkJJx3LDACgAgALAAkJJx3LDACgAgAAAA==.Ausser:BAAALgADCgQJAwAAAA==.',
Ax='Axehand:BAAALgAECgMJBAAAAA==.',
Az='Azarine:BAACLgAFFH8LAAICAAMJdQt8HABxAAACAAMJdQt8HABxAAAuAAQKfyEAAgIACAnXC0IoAJcBAAIACAnXC0IoAJcBAAAA.Azend:BAAALgAECgIJAgAAAA==.Azphrodite:BAAALgAECgYJBgAAAA==.Azralia:BAABLgAECn8eAAMMAAkJpxXLGgAuAgAMAAkJpxXLGgAuAgANAAEJFg6PZwAtAAAAAA==.',
Ba='Baconator:BAAALgAECgEJAQAAAA==.Barthamus:BAAALgADCgYJBgAAAA==.',
Bb='Bbygee:BAAALgAECgYJEwAAAA==.',
Be='Bearlyshådow:BAAALgADCgUJBQAAAA==.Beastlegion:BAAALgADCgYJFQAAAA==.Beaverboys:BAAALgADCgEJAQAAAA==.Bella:BAAALgAECgcJEwAAAA==.Benjaminadin:BAAALgAECgUJEQAAAA==.Berris:BAAALgADCgYJBgAAAA==.Beyblade:BAAALgAECgQJBQAAAA==.',
Bi='Bigstones:BAAALgADCgYJDAAAAA==.Bimbobanger:BAAALgAECgQJBQAAAA==.',
Bj='Bjorn:BAAALgADCgYJBwAAAA==.',
Bl='Blazinember:BAABLgAECn8+AAIOAAkJJAwXBQCMAQAOAAkJJAwXBQCMAQAAAA==.Bloodguzzler:BAAALgAECgMJAwAAAA==.Blueberri:BAAALgAECgMJAwAAAA==.',
Bo='Bobbydrac:BAAALgADCgIJAgAAAA==.Boggy:BAABLgAECn8cAAQPAAkJUxcgMgBtAQAPAAcJShQgMgBtAQAJAAcJiwpaKgAfAQAQAAEJsiCEHQBiAAAAAA==.Boop:BAAALgADCgkJCQABLgAECgkJNAANADkkAA==.Borgin:BAABLgAECn8VAAIDAAYJ3QaVtwDWAAADAAYJ3QaVtwDWAAAAAA==.Borgofdeth:BAAALgAECgIJAgAAAA==.Borimor:BAABLgAECn8fAAINAAcJcAxFpgAuAQANAAcJcAxFpgAuAQABLgAECgkJFgADAKoQAA==.Bowehunter:BAAALgAECgEJAQAAAA==.',
Br='Braina:BAAALgAECgEJAQAAAA==.Braylia:BAAALgADCggJCAAAAA==.Briaella:BAABLgAECn8eAAMRAAYJwhHJOQAVAQARAAYJwhHJOQAVAQASAAEJuAMHiQAmAAABLgAECgkJQQATAPocAA==.Bridgetta:BAAALgAECgIJAgAAAA==.Brisli:BAAALgADCgcJBwABLgAECgkJHQALACcdAA==.Briëlla:BAABLgAECn9BAAQTAAkJ+hyOGQCtAgATAAkJ+hyOGQCtAgAUAAEJDQjpQAAlAAAVAAEJOgMAbQASAAAAAA==.Bromdrago:BAAALgAECgEJAQAAAA==.Bromkin:BAABLgAECn8ZAAIWAAkJIxujBQA3AQAWAAkJIxujBQA3AQAAAA==.',
Bu='Bubonics:BAAALgAECgUJBQAAAA==.',
['Bë']='Bëorn:BAAALgAECgUJBQABLgAECgkJFgADAKoQAA==.',
Ca='Calindala:BAAALgADCggJBAAAAA==.Calinor:BAABLgAECn8cAAINAAYJTRNKFQAyAQANAAYJTRNKFQAyAQAAAA==.Carl:BAAALgAECgkJEQAAAA==.Case:BAAALgADCgEJAQAAAA==.Castandie:BAABLgAECn8aAAIXAAYJCQeG8AAZAQAXAAYJCQeG8AAZAQAAAA==.',
Ce='Ceran:BAABLgAECn8yAAIYAAkJ6hNDFADvAQAYAAkJ6hNDFADvAQAAAA==.Cereus:BAACLgAFFH8PAAMJAAQJMByuCABJAQAJAAQJMByuCABJAQAQAAIJpwwDCgCHAAAuAAQKf0oAAwkACQkXJPMAAKsDAAkACQkXJPMAAKsDABAACQmEHOgCAH4CAAAA.',
Ch='Chaelenge:BAABLgAECn8lAAMMAAkJSh5iCAAFAwAMAAkJSh5iCAAFAwANAAMJpQlLWwFWAAAAAA==.Charles:BAAALgAECgkJAwAAAA==.Cheatt:BAAALgAECgEJAQAAAA==.Chyran:BAABLgAECn8aAAMNAAgJAQy4HAD5AAANAAgJAQy4HAD5AAAMAAIJHRY5bQCBAAAAAA==.',
Cl='Clock:BAAALgAFFAEJAQAAAA==.Cloeh:BAAALgAECgEJAQAAAA==.',
Co='Cocobutters:BAAALgADCgEJAQAAAA==.Coloratura:BAABLgAECn8uAAIBAAkJeBlAAwASAgABAAkJeBlAAwASAgAAAA==.Corydh:BAAALgAECgYJEAAAAA==.',
Cp='Cptkanuckles:BAAALgAFFAIJAwAAAA==.',
Cr='Crazyelf:BAAALgADCgQJCAAAAA==.Crimsonmoon:BAAALgAECggJCAABLgAECgkJNAANADkkAA==.Crunchbar:BAAALgADCgUJBQAAAA==.',
Cu='Cubscout:BAAALgADCgcJBwAAAA==.Cutecop:BAAALgAECgIJBAAAAA==.',
['Có']='Cóffee:BAAALgADCgkJCQAAAA==.',
Da='Dagast:BAAALgADCgYJCQAAAA==.Dagethon:BAAALgAECgIJAQAAAA==.Dalielah:BAAALgAECgUJCAAAAA==.Danfortesque:BAAALgADCgIJAgAAAA==.Darkkstarr:BAAALgAECgUJBwAAAA==.Daromiciah:BAAALgAECgIJAgAAAA==.',
De='Deathnome:BAAALgADCgYJAwAAAA==.Demdots:BAAALgADCgEJAQAAAA==.Denvoker:BAABLgAECn8VAAQJAAgJBg4dHwD+AAAJAAYJrAodHwD+AAAPAAMJ5gU+GQBDAAAQAAEJAADhLwAAAAAAAA==.Deputyfluff:BAAALgADCgEJAQAAAA==.Derathull:BAAALgAECgQJBAAAAA==.Desmac:BAAALgAECgYJBgABLgAFFAIJAgAZAAAAAA==.',
Dh='Dhjacob:BAAALgAECgYJEQAAAA==.',
Di='Diddykong:BAAALgAECgkJCQAAAA==.Dirtnapp:BAAALgADCgEJAgAAAA==.',
Do='Docqt:BAAALgADCgEJAQAAAA==.Dolleez:BAAALgAECgcJCAAAAA==.Doodridder:BAAALgAECgQJBAAAAA==.Dooman:BAAALgADCgcJDAAAAA==.Dotpockets:BAAALgAECgUJBQAAAA==.Dotsenpai:BAAALgADCgQJBQAAAA==.Doubtfire:BAABLgAECn9DAAMEAAkJbwYvDwDMAAAEAAkJbwYvDwDMAAAaAAIJiAE6+AAbAAAAAA==.',
Dr='Dragii:BAAALgAECgMJBAAAAA==.',
Du='Dunkaroo:BAABLgAECn8eAAIbAAkJMhQFRAC8AQAbAAkJMhQFRAC8AQAAAA==.',
['Dé']='Dékü:BAAALgAECgcJCgAAAA==.',
Ei='Eikinskaldi:BAAALgAECgEJAgAAAA==.',
El='Elcarly:BAAALgAECgEJAgAAAA==.Eleridus:BAAALgADCgMJAwAAAA==.Elphysa:BAAALgADCgQJBAAAAA==.',
Em='Empty:BAABLgAECn8mAAINAAkJ5gzsdgCAAQANAAkJ5gzsdgCAAQAAAA==.',
En='Endormu:BAAALgAECgIJAgAAAA==.',
Ep='Epiduralrot:BAACLgAFFH8SAAQcAAYJbBPZDQDGAAAcAAQJLAjZDQDGAAAdAAMJYhBYhAC9AAAeAAIJlyBVDwCYAAAuAAQKfycABB0ACAnCILguAFICAB0ACAlCHbguAFICABwABAn1GWAiAEMBAB4AAwlJIsUSAAABAAAA.',
Er='Eraessyr:BAAALgAECgQJBAAAAA==.Erind:BAAALgADCgcJBwAAAA==.',
Et='Etërnal:BAAALgADCgkJDwAAAA==.',
Fa='Fabiand:BAAALgAECgIJAgAAAA==.Faithful:BAAALgAECgkJBwAAAA==.Faithfulness:BAAALgAECgEJAQAAAA==.Faiye:BAAALgAECggJCgAAAA==.Fandris:BAAALgAECgEJAQAAAA==.',
Fe='Feldrus:BAAALgAECgMJBAABLgAECgkJRwAfAOEVAA==.Fendre:BAAALgADCgEJAQAAAA==.',
Fl='Flaregun:BAAALgAECgIJAwABLgAECgkJEQAZAAAAAA==.',
Fo='Forsëti:BAAALgAECgIJAgAAAA==.',
Fr='Freakadeek:BAAALgAECgMJBAABLgAECgkJFQAUAGsNAA==.Frosh:BAABLgAECn8ZAAMIAAgJ/hF2OACgAQAIAAgJ/hF2OACgAQAgAAMJ4h2/bQCMAAAAAA==.Frìeren:BAABLgAECn8oAAIXAAkJ1hNMUwDjAQAXAAkJ1hNMUwDjAQAAAA==.',
Fu='Fuegaluna:BAAALgADCgkJCwAAAA==.Fundetected:BAACLgAFFH8IAAIbAAMJOA2nbQCvAAAbAAMJOA2nbQCvAAAuAAQKfywAAhsACQmYHJYeAF0CABsACQmYHJYeAF0CAAAA.',
['Fâ']='Fâllenboy:BAAALgAECgMJAwAAAA==.',
Ga='Garross:BAAALgADCgYJCAAAAA==.',
Ge='Geoffrii:BAAALgADCgcJBwAAAA==.',
Gh='Ghouldottie:BAAALgAECgMJAwAAAA==.',
Gi='Gilidar:BAABLgAECn8xAAMhAAkJ1yTkAgARAwAhAAkJ/yPkAgARAwAFAAYJ2yNsNAB5AQAAAA==.Gillarria:BAABLgAECn8UAAMiAAYJoRDaAgBTAQAiAAYJoRDaAgBTAQAYAAEJnAi/eQAmAAAAAA==.',
Gn='Gnomerdenis:BAAALgADCgUJBgAAAA==.',
Go='Goochiemon:BAAALgAECgQJBAAAAA==.Gotalight:BAAALgAECgcJCAAAAA==.',
Gr='Gravecrawler:BAAALgAECgYJBQAAAA==.Grimmberly:BAAALgAECgcJDAABLgAECgkJGgAKACMcAA==.Grimmothy:BAABLgAECn8sAAIRAAkJ3BafEgAfAgARAAkJ3BafEgAfAgABLgAECgkJGgAKACMcAA==.Grimoire:BAABLgAECn8aAAIKAAkJIxxIAQCIAgAKAAkJIxxIAQCIAgAAAA==.Grindr:BAAALgAECgIJAgAAAA==.',
Gu='Guanyin:BAAALgAECgEJAQAAAA==.Gutdrunel:BAAALgAECgMJAwAAAA==.Guthumwar:BAAALgAECgYJCAAAAA==.Guthunnel:BAABLgAECn86AAIDAAkJvhIgOgD2AQADAAkJvhIgOgD2AQAAAA==.Gutshadra:BAAALgAECgcJBgAAAA==.',
['Gö']='Göldenvenom:BAAALgADCgQJBAAAAA==.',
Ha='Haides:BAAALgAECgIJAgAAAA==.Hakuri:BAAALgADCgcJDwABLgAECgYJDQAZAAAAAA==.Hannibow:BAAALgAECgcJCAAAAA==.Happydru:BAAALgADCgcJDgAAAA==.Havic:BAAALgADCgYJBgAAAA==.Hazuki:BAAALgAECgEJAgAAAA==.',
He='Helle:BAABLgAECn8gAAQfAAkJuxRaHQAuAgAfAAkJuxRaHQAuAgARAAYJ6Aj0TQALAQASAAIJ7g8rFgBdAAAAAA==.Hellgrim:BAAALgADCgEJAQABLgAECgkJGgAKACMcAA==.',
Hi='Highfever:BAABLgAECn8UAAIaAAUJ3A32cADiAAAaAAUJ3A32cADiAAAAAA==.',
Ho='Hoawatt:BAAALgAECgQJBQAAAA==.Holynova:BAAALgADCgQJBwABLgAECgQJBAAZAAAAAA==.Hoofkick:BAAALgAECgIJAgAAAA==.',
Hr='Hrum:BAAALgADCgEJAQAAAA==.',
Hu='Hubbaroo:BAAALgADCgQJBAABLgAECgkJMwAaAIIbAA==.Huuch:BAABLgAECn8oAAIDAAkJEAs4VgChAQADAAkJEAs4VgChAQAAAA==.',
Hy='Hycinari:BAAALgAECgIJAgAAAA==.Hyperius:BAAALgAECgUJBQAAAA==.',
Ic='Icrucify:BAACLgAFFH8FAAIDAAMJ6RwlFQCwAAADAAMJ6RwlFQCwAAAuAAQKfzkAAgMACQmgJUQIABkDAAMACQmgJUQIABkDAAAA.',
Ig='Ignee:BAABLgAFFH8IAAMjAAMJRBPfFQB0AAAFAAMJpAT/PgCsAAAjAAIJnBjfFQB0AAAAAA==.Ignia:BAAALgAECgIJAgABLgAECggJCgAZAAAAAA==.',
Il='Ilanos:BAAALgAECgIJAgAAAA==.',
Im='Imeria:BAAALgAECgQJBgAAAA==.Imissmobo:BAAALgADCgIJAgAAAA==.',
In='Inhyai:BAAALgAECgMJAwABLgAFFAQJBAAZAAAAAA==.',
Ir='Iremoon:BAABLgAECn88AAMTAAkJkxWwNgAkAgATAAkJkxWwNgAkAgAVAAIJRwQTQgBCAAABLgAFFAMJCwANADgMAA==.Iridio:BAAALgAECgYJBgAAAA==.',
Ja='Jadexx:BAAALgAECgMJAwAAAA==.Jaeler:BAAALgAECggJDgAAAA==.',
Je='Jedistang:BAAALgAECgQJBgAAAA==.Jestyr:BAACLgAFFH8RAAMYAAQJaRgiDgA1AQAYAAQJaRgiDgA1AQAiAAIJAxUUBwCEAAAuAAQKfxYAAxgACQlUH2IGANECABgACQlUH2IGANECABsAAQmBB28oASUAAAAA.Jestyrd:BAAALgAECgMJAwABLgAFFAQJEQAYAGkYAA==.Jestyrdk:BAABLgAECn8UAAITAAgJrR9ZBAB2AgATAAgJrR9ZBAB2AgABLgAFFAQJEQAYAGkYAA==.Jestyrmo:BAABLgAECn8rAAMRAAgJARtiJQCDAQARAAcJ2BliJQCDAQAfAAgJgBCxRABZAQABLgAFFAQJEQAYAGkYAA==.',
Ji='Jitjitjitjit:BAAALgAECgEJAQAAAA==.Jiyao:BAACLgAFFH8eAAISAAQJ4R/yCwBmAQASAAQJ4R/yCwBmAQAuAAQKf0wAAxIACQnwJKgCAEADABIACQnwJKgCAEADAB8AAQmeB+tsACgAAAAA.',
Jo='Jodi:BAAALgAECgYJEwAAAA==.',
Ju='Jules:BAAALgAFFAIJAgAAAA==.Jumbo:BAAALgAECgMJBAABLgAECgQJBQAZAAAAAA==.',
Ka='Kaceya:BAAALgAECgUJDQAAAA==.Kainarasa:BAAALgAECgYJEwABLgAECgkJNAANADkkAA==.Kairn:BAAALgADCggJDAAAAA==.Kairnei:BAAALgADCgYJEgAAAA==.Katarinea:BAABLgAECn8fAAIEAAkJiw7DKgB/AQAEAAkJiw7DKgB/AQAAAA==.Kaypop:BAAALgAECgcJEwAAAA==.',
Ke='Keats:BAAALgAECgIJAgAAAA==.Keeytz:BAAALgADCgYJAgAAAA==.',
Kh='Khalessie:BAABLgAECn8lAAILAAkJOQ3PIwCwAQALAAkJOQ3PIwCwAQAAAA==.Kheldar:BAAALgAECgkJAwAAAA==.Khrone:BAAALgAECgEJAgAAAA==.',
Ki='Kirsi:BAABLgAECn8kAAMkAAkJpB5LCABBAgAkAAkJpB5LCABBAgAIAAEJeQHi9gAZAAAAAA==.Kiselle:BAAALgAECgQJBAABLgAECgkJHQALACcdAA==.',
Kl='Klorick:BAAALgAECgYJBgABLgAECgkJFgADAKoQAA==.',
Ko='Koonu:BAABLgAFFH8FAAIMAAMJ/RI/FQC1AAAMAAMJ/RI/FQC1AAABLgAECgkJGQAIALcZAA==.Korkneelious:BAAALgAECgYJDAAAAA==.',
Kr='Kretor:BAAALgAECgQJDgABLgAECgkJGQAIALcZAA==.',
Ku='Kungfudru:BAAALgAECgEJAQAAAA==.',
Kw='Kwai:BAAALgAECgYJBgABLgAECgkJFgADAKoQAA==.',
Ky='Kyomu:BAAALgAECgcJBwABLgAECgkJNAANADkkAA==.',
La='Lavendarmoon:BAAALgAECgEJAQAAAA==.',
Li='Lillock:BAAALgAECgIJAgAAAA==.Lineofsight:BAABLgAECn9QAAIFAAgJzh2aAgBNAgAFAAgJzh2aAgBNAgAAAA==.Liths:BAABLgAECn87AAIiAAkJlAlIEQA4AQAiAAkJlAlIEQA4AQAAAA==.Littlemoses:BAABLgAECn8nAAIDAAkJiRsuLwAgAgADAAkJiRsuLwAgAgAAAA==.',
Lo='Lockdarkly:BAAALgAECgUJCQAAAA==.Lono:BAAALgADCgQJBwAAAA==.Lostdru:BAAALgADCgEJAgAAAA==.',
Lu='Lululuvely:BAABLgAECn8VAAMLAAYJIxV5KQCIAQALAAYJIxV5KQCIAQABAAUJZwk5UwDqAAAAAA==.Lulzimadrood:BAAALgADCgMJAwAAAA==.',
Ma='Machrona:BAAALgAECgEJAQAAAA==.Magejacob:BAAALgADCgcJCQABLgAECgYJEQAZAAAAAA==.Malendren:BAAALgAECgEJAQAAAA==.Malignus:BAACLgAFFH8HAAIXAAQJdRDQLQAWAQAXAAQJdRDQLQAWAQAuAAQKfz8AAhcACQk3ISUDAOECABcACQk3ISUDAOECAAEuAAMKCQkXABkAAAAA.Malthaos:BAAALgADCgQJBAABLgAECgkJJwAXAAIdAA==.Maneyen:BAAALgADCgQJAwAAAA==.Margot:BAAALgAECgYJEgAAAA==.Marksmann:BAAALgAECgIJBQAAAA==.Marriah:BAAALgAECgQJBAABLgAECgkJJwADAIkbAA==.Mavane:BAAALgADCgUJAQAAAA==.Mawhriccio:BAAALgAECgEJAQAAAA==.',
Mc='Mcdavé:BAABLgAECn88AAIgAAkJyxCNJwCwAQAgAAkJyxCNJwCwAQAAAA==.',
Me='Meathshield:BAAALgADCgMJAwABLgAECggJHgACAIIcAA==.Meerclar:BAAALgAECgIJAwABLgAECggJDwAZAAAAAA==.Melaila:BAABLgAECn9WAAIIAAkJISNXAgDMAgAIAAkJISNXAgDMAgAAAA==.Mellwynn:BAAALgAECgUJDwAAAA==.Melunaura:BAAALgAECggJCQABLgAECgkJVgAIACEjAA==.Menalaus:BAAALgAECgUJBQAAAA==.',
Mf='Mf:BAABLgAECn8hAAIbAAcJtxRaaABVAQAbAAcJtxRaaABVAQAAAA==.',
Mi='Micheal:BAAALgAFFAIJAgAAAA==.Midir:BAAALgAECgQJBAAAAA==.Miladrayn:BAAALgADCgcJFgAAAA==.Mimikyu:BAAALgAFFAEJAQABLgAFFAcJIAAgAJwdAA==.Min:BAAALgAECgIJAgAAAA==.Minthe:BAAALgAECgQJBQAAAA==.Mistwallker:BAAALgADCgUJBQAAAA==.Miñitañk:BAAALgAECgIJAgAAAA==.',
Mo='Moardotz:BAAALgADCgUJBgAAAA==.Moldthinur:BAABLgAECn84AAIWAAkJbSVZAAA2AwAWAAkJbSVZAAA2AwAAAA==.Mongrol:BAAALgAECgQJBgAAAA==.Monju:BAAALgAECgEJAQAAAA==.Monôpolyguy:BAAALgAECgIJAgAAAA==.Moonowl:BAAALgAECgQJBgAAAA==.Mordrack:BAAALgAECgYJBgAAAA==.Moreganna:BAAALgADCgYJCQABLgAECgUJFAAaANwNAA==.',
Mu='Mummrakhan:BAABLgAECn8dAAIdAAkJHgWlpgD0AAAdAAkJHgWlpgD0AAAAAA==.Murraya:BAAALgADCgcJBwAAAA==.',
Na='Nagasaki:BAAALgAECgkJDQABLgAECgkJEQAZAAAAAA==.Naniel:BAACLgAFFH8ZAAIFAAUJ2g6CJQAfAQAFAAUJ2g6CJQAfAQAuAAQKfy0AAwUACQmLGMMdAAACAAUACQmDFsMdAAACACMABAneG20FADkBAAAA.Narmaya:BAAALgADCgMJAwAAAA==.',
Ne='Neat:BAAALgAECgcJBwABLgAFFAMJBAAZAAAAAA==.Neb:BAACLgAFFH8TAAIdAAQJ/g8jKwDcAAAdAAQJ/g8jKwDcAAAuAAQKf0oAAx0ACQnHHJUYAJACAB0ACQnHHJUYAJACABwAAgm5EVZXAGgAAAAA.Necroy:BAABLgAECn8VAAIcAAkJCh6rAgCHAgAcAAkJCh6rAgCHAgAAAA==.Netheris:BAAALgAECgEJAQAAAA==.',
Ni='Niccee:BAABLgAECn8iAAIEAAkJrwwgKwB8AQAEAAkJrwwgKwB8AQAAAA==.Nick:BAACLgAFFH8RAAIdAAUJ+BuIEQBYAQAdAAUJ+BuIEQBYAQAuAAQKfxgAAx0ACAkYIykbALECAB0ACAkYIykbALECABwAAQkAAHuAABAAAAAA.Nightflurry:BAAALgAECgcJEgAAAA==.Nightslife:BAAALgADCgUJBQABLgADCgUJBQAZAAAAAA==.',
No='Noodles:BAAALgAECgcJEgABLgAECggJIgAbAH0WAA==.Nosebleeds:BAABLgAECn8VAAMKAAgJCh3nEADcAQAKAAcJdxznEADcAQAlAAIJfxw8RQBRAAAAAA==.Notyourheals:BAABLgAECn8wAAMgAAgJ2BEIMgB1AQAgAAgJ2BEIMgB1AQAIAAQJSAGjjQBfAAAAAA==.',
Oa='Oakay:BAAALgAECgMJAwAAAA==.',
Ob='Obee:BAABLgAECn8nAAIaAAkJNxZAKgADAgAaAAkJNxZAKgADAgAAAA==.',
Od='Odette:BAAALgADCgYJBgAAAA==.Odsum:BAABLgAECn8XAAINAAYJWBpciwBaAQANAAYJWBpciwBaAQAAAA==.',
Om='Ombo:BAAALgAECgMJAwAAAA==.Omegasupreme:BAAALgAECgIJAgAAAA==.',
Oo='Oogrutamu:BAAALgAECgIJAgAAAA==.',
Or='Orionna:BAAALgADCggJBAAAAA==.',
Pa='Pal:BAAALgAECgEJAQAAAA==.Palanious:BAAALgAECgMJBgAAAA==.Pandabear:BAAALgADCgkJDwAAAA==.Papamidnight:BAAALgAECgIJAwAAAA==.Papasmurff:BAAALgADCgIJAgAAAA==.Papichulo:BAAALgAECgIJAgAAAA==.',
Pe='Percival:BAABLgAECn8mAAINAAkJUA2bbgCRAQANAAkJUA2bbgCRAQAAAA==.',
Pi='Pinheadjerry:BAAALgAECgEJAQAAAA==.Pinhêadlarry:BAAALgADCgYJBgAAAA==.Pizzaslice:BAABLgAECn80AAINAAkJOSRIBgA/AwANAAkJOSRIBgA/AwAAAA==.',
Po='Poetbrat:BAAALgADCgkJIQABLgAECgkJQwAEAG8GAA==.Porkles:BAAALgADCgQJBQAAAA==.',
Pr='Praxiscannon:BAAALgAECgUJBgAAAA==.Prettydead:BAAALgADCgIJAgAAAA==.',
Pu='Pumpshire:BAABLgAECn8jAAIQAAkJswsyCgB9AQAQAAkJswsyCgB9AQAAAA==.',
Pw='Pwnstar:BAAALgADCgMJAwAAAA==.Pwongo:BAACLgAFFH8PAAIaAAQJBx2hDQBTAQAaAAQJBx2hDQBTAQAuAAQKf0MAAxoACAnUIGsBAO4CABoACAnUIGsBAO4CAAQAAgkgAqCqABMAAAAA.',
Qu='Queue:BAABLgAECn8jAAIcAAYJLBWtBAAmAQAcAAYJLBWtBAAmAQAAAA==.Quilten:BAABLgAECn8cAAISAAcJuA08OwAUAQASAAcJuA08OwAUAQAAAA==.',
Ra='Raenii:BAAALgAFFAEJAwABLgAFFAIJBgABAMMSAA==.Ramoth:BAABLgAECn8VAAIgAAgJrQcNZAC5AAAgAAgJrQcNZAC5AAAAAA==.Ranoe:BAAALgADCgcJDQAAAA==.Rapids:BAAALgADCgYJCAAAAA==.Rashamka:BAAALgAECgIJAgAAAA==.Rasputan:BAAALgAECgEJAQAAAA==.Rayne:BAABLgAECn8nAAIXAAkJAh0gLwBcAgAXAAkJAh0gLwBcAgAAAA==.Razelda:BAAALgAECgkJCAAAAA==.',
Re='Reolz:BAAALgADCgUJBAAAAA==.Reveya:BAABLgAECn8pAAMUAAkJJRbLAQAPAgAUAAkJJRbLAQAPAgATAAcJng6wpQAjAQAAAA==.',
Ri='Rinnian:BAAALgAECgYJDwAAAA==.Rinny:BAAALgAECgEJAQAAAA==.Riptideaf:BAAALgAECgEJAQAAAA==.',
Ro='Roadwanderer:BAAALgAECgcJEgAAAA==.Robbiedrake:BAAALgAECgEJAQABLgAFFAQJBwASAGMNAA==.Robbiemonk:BAACLgAFFH8HAAMSAAQJYw0lGwBUAAASAAQJGQclGwBUAAARAAIJXBJaIQA/AAAuAAQKf0gAAxEACQlTG1cMAHACABEACQlTG1cMAHACABIABAn3AxNeAJgAAAAA.Robbiesboomy:BAAALgAECgIJAgABLgAFFAQJBwASAGMNAA==.Rodric:BAAALgAECgUJBQABLgAECgkJFgADAKoQAA==.Rokage:BAAALgADCgYJCwAAAA==.',
Ru='Runed:BAAALgAECgYJCQAAAA==.Runetottem:BAAALgADCgEJAQAAAA==.',
Rx='Rxeight:BAAALgAECgYJBgAAAA==.',
Sa='Sakura:BAAALgAECgcJDwAAAA==.Sannith:BAABLgAECn86AAIXAAkJUxasOQAyAgAXAAkJUxasOQAyAgAAAA==.Sapphi:BAABLgAECn8lAAIWAAkJew/PFACEAQAWAAkJew/PFACEAQAAAA==.Sarjarus:BAAALgADCgYJAgAAAA==.',
Se='Seespottank:BAABLgAECn8lAAIhAAkJ2BHvAgCRAQAhAAkJ2BHvAgCRAQAAAA==.Senjinbenjin:BAAALgAECgQJBQAAAA==.',
Sh='Shadowallker:BAAALgADCgMJAwABLgADCgUJBQAZAAAAAA==.Shadowlich:BAAALgAECgYJBgAAAA==.Shakjabuti:BAAALgADCgUJBQAAAA==.Shamanoodles:BAAALgAECgkJEQABLgAECgkJVgAIACEjAA==.Sharma:BAAALgAECgcJBwABLgAECgkJGQAIALcZAA==.Shattersun:BAAALgAECgQJAgAAAA==.Shauralin:BAAALgAECgEJAQAAAA==.Shelbei:BAAALgAECgQJBgAAAA==.Shespawn:BAAALgAFFAIJBAAAAA==.Shoukkan:BAAALgADCgcJBwAAAA==.Shurie:BAABLgAECn8WAAMDAAkJqhDkLwDxAQADAAkJqhDkLwDxAQAmAAEJLQJiMgApAAAAAA==.Shykara:BAAALgADCgcJGAABLgAECggJFQAgAK0HAA==.Shâdê:BAAALgAECgEJBAAAAA==.Shådowblade:BAAALgADCgkJCQAAAA==.',
Si='Sinae:BAAALgAECgEJAQAAAA==.Sindrak:BAAALgAECgEJAgAAAA==.Sins:BAAALgAECgIJAgAAAA==.Sinsorain:BAAALgADCgEJAQAAAA==.Sipsy:BAAALgAECgcJBQAAAA==.',
Sk='Skulcrack:BAAALgADCgcJDgAAAA==.',
Sl='Slabomeat:BAAALgAECgcJBwABLgAECgkJFgADAKoQAA==.Slipperybop:BAACLgAFFH8PAAINAAMJ4CT7QAApAQANAAMJ4CT7QAApAQAuAAQKfxwAAg0ACQlgI/sJABcDAA0ACQlgI/sJABcDAAEuAAUUAQkDABkAAAAA.Slugbow:BAAALgAECgYJCQAAAA==.',
Sm='Smashed:BAAALgAFFAIJAgABLgAFFAIJAgAZAAAAAA==.',
Sn='Snakeshadow:BAAALgAECgMJAwAAAA==.Snoom:BAABLgAECn8kAAIIAAkJZAYVcQAJAQAIAAkJZAYVcQAJAQAAAA==.',
So='Soldanis:BAAALgAFFAEJAgAAAA==.Sorena:BAAALgAECgMJAwAAAA==.',
Sp='Spawny:BAAALgADCgYJBgAAAA==.Spazoff:BAAALgAECgUJDQAAAA==.Spyman:BAAALgAECgEJBAAAAA==.Spyro:BAAALgAECgMJAwAAAA==.',
Sr='Srhubbabubba:BAABLgAECn8zAAIaAAkJghv7EQC/AgAaAAkJghv7EQC/AgAAAA==.',
St='Starz:BAAALgADCgkJCQAAAA==.Staticbdk:BAAALgAECgEJAQABLgAFFAQJBAAZAAAAAA==.Statickling:BAAALgAFFAQJBAAAAA==.Steamynix:BAAALgADCgUJBQAAAA==.Sternn:BAAALgAECgEJAgAAAA==.Steviathan:BAAALgAECgYJDAAAAA==.Straif:BAAALgAECgQJBwAAAA==.',
Sv='Sveliaa:BAAALgAECgIJAgABLgAFFAQJBAAZAAAAAA==.',
Sw='Sweetest:BAAALgAECgYJBwAAAA==.Swolman:BAAALgADCgYJBgAAAA==.',
Sy='Sydeon:BAAALgAECgYJEQAAAA==.Syndra:BAAALgAECgEJAQABLgAECggJCgAZAAAAAA==.',
Ta='Tanderina:BAAALgAECgIJAgAAAA==.Tankshock:BAABLgAFFH8FAAIjAAIJTQIEHABIAAAjAAIJTQIEHABIAAAAAA==.Taylor:BAAALgAECgcJAgABLgAFFAUJCwACADwcAA==.',
Te='Teddy:BAAALgAECgMJBAAAAA==.Tellah:BAABLgAECn8ZAAMIAAkJtxk7FwCPAgAIAAkJtxk7FwCPAgAgAAUJ/wk5YwC2AAAAAA==.Tellairion:BAAALgADCgYJCQAAAA==.',
Th='Thegodofwar:BAAALgADCggJCQAAAA==.Thegreatland:BAAALgAECgMJAwAAAA==.Theiren:BAAALgAECgEJAQAAAA==.Themuffinman:BAAALgAECgkJEQABLgAECgkJNAANADkkAA==.',
To='Tongari:BAAALgADCgQJBAAAAA==.',
Tu='Tullinnelor:BAAALgADCgEJAQABLgAECgkJGwABABwRAA==.',
Tw='Twomz:BAACLgAFFH8IAAIIAAMJ/gZcNwBtAAAIAAMJ/gZcNwBtAAAuAAQKfzUAAwgACQkdEX8uAPwBAAgACQkdEX8uAPwBACAABQlQDRcTAK8AAAAA.',
Um='Umi:BAAALgAECgEJAQABLgAFFAMJBwAIAOMVAA==.',
Un='Unclebenjin:BAAALgAECgYJBgAAAA==.Unkadier:BAAALgADCgMJAwABLgAECgkJFwAXAA0hAA==.',
Va='Varkbyte:BAAALgAECgMJAwAAAA==.Varock:BAAALgAECgcJBwABLgAECgkJNAANADkkAA==.Varrieto:BAAALgAECgcJBwAAAA==.Vavaboom:BAAALgADCggJCAAAAA==.',
Ve='Veirlyn:BAAALgAECgkJCQAAAA==.',
Vi='Vindication:BAABLgAECn8jAAIMAAgJ9iJ8BwAUAwAMAAgJ9iJ8BwAUAwAAAA==.Viz:BAAALgADCgkJIQAAAA==.',
Vo='Voidshådow:BAABLgAECn8XAAIbAAcJmxOBXwBrAQAbAAcJmxOBXwBrAQAAAA==.Voreho:BAAALgADCggJCAAAAA==.',
Vr='Vraul:BAAALgAECgMJAgABLgAECgkJJwAXAAIdAA==.',
Vu='Vulpain:BAABLgAECn8XAAIIAAkJPxowAwCNAgAIAAkJPxowAwCNAgABLgAECgkJNAANADkkAA==.',
Vy='Vylandra:BAAALgAECgQJBQAAAA==.',
We='Weepingwillo:BAAALgAECgQJBAAAAA==.Wennon:BAAALgADCgQJBAAAAA==.',
Wh='Whatsituya:BAAALgADCgcJCwAAAA==.Where:BAAALgAECgUJCgABLgAECgkJEQAZAAAAAA==.Whiteangel:BAAALgAECgEJAQAAAA==.',
Wi='Willythewolf:BAAALgADCgEJAQAAAA==.Willywallace:BAAALgAECggJCQAAAA==.Wiseman:BAAALgAECgMJAwAAAA==.',
Wo='Wolfowl:BAABLgAECn8XAAIEAAUJXQdIGABrAAAEAAUJXQdIGABrAAAAAA==.',
Xa='Xaela:BAABLgAECn8dAAIbAAkJEhcYOQDiAQAbAAkJEhcYOQDiAQAAAA==.Xantriar:BAAALgADCgUJBQAAAA==.Xarbariste:BAAALgAECggJDwAAAA==.Xarous:BAAALgAECgkJCQABLgAECgkJNAANADkkAA==.',
Xe='Xeon:BAAALgAECgUJDQAAAA==.',
Xi='Xiabal:BAACLgAFFH8IAAMEAAMJYhSlFgDOAAAEAAMJYhSlFgDOAAAaAAIJ4QlhJwBTAAAuAAQKfy4AAxoACQnTHlIJACQDABoACQnTHlIJACQDAAQABAmQG7QMAO8AAAAA.',
Xw='Xweakling:BAAALgAECgcJDAABLgAFFAQJEAAFAEobAA==.Xweekling:BAACLgAFFH8QAAIFAAQJShu8GQBLAQAFAAQJShu8GQBLAQAuAAQKfy4AAgUACQnyIyMDADsDAAUACQnyIyMDADsDAAAA.Xweeklingdh:BAAALgAECgYJBgABLgAFFAQJEAAFAEobAA==.',
Xy='Xynoria:BAAALgAECgEJAQAAAA==.',
Ye='Yendara:BAAALgAECgEJAQAAAA==.Yetihunter:BAAALgADCgMJBAAAAA==.',
Yu='Yuxiong:BAAALgADCgkJIAAAAA==.',
Za='Zaraeth:BAAALgAECgUJDAABLgAECggJDwAZAAAAAA==.',
Ze='Zedra:BAAALgAECgQJEgAAAA==.Zenhubba:BAAALgAECgYJBgABLgAECgkJMwAaAIIbAA==.Zerostar:BAABLgAECn8XAAImAAcJshEHLQA9AQAmAAcJshEHLQA9AQABLgAECgkJNAADAIEfAA==.Zevon:BAAALgAECgIJAgABLgAECggJDwAZAAAAAA==.',
['ße']='ßeastie:BAAALgADCgcJCwAAAA==.',
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
