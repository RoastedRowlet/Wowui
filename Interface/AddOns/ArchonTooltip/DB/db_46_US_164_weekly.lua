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

local lookup = {'Unknown-Unknown','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Druid-Balance','Warrior-Fury','Shaman-Restoration','Evoker-Preservation','Druid-Guardian','Priest-Discipline','Paladin-Holy','Paladin-Retribution','Mage-Fire','Evoker-Augmentation','Evoker-Devastation','Rogue-Assassination','Rogue-Subtlety','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Protection','Mage-Frost','DemonHunter-Havoc','Druid-Restoration','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Monk-Mistweaver','Shaman-Elemental','Warrior-Arms','DemonHunter-Vengeance','Warrior-Protection','Shaman-Enhancement','Druid-Feral','Hunter-Survival',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=46,date='2026-08-25',data={Ab='Abbaddon:BAAALgADCgcJBwAAAA==.Aberration:BAAALgADCgMJAwAAAA==.Absolutezero:BAAALgADCggJFAAAAA==.',
Ad='Addison:BAAALgAECgQJBQABLgAECgYJEwABAAAAAA==.Adicia:BAAALgAECgMJAwAAAA==.Adormi:BAAALgAECgQJBQAAAA==.',
Ae='Aestel:BAAALgADCgEJAQAAAA==.',
Ai='Aidum:BAAALgADCgMJAwAAAA==.',
Al='Alarus:BAAALgADCgYJCAAAAA==.Algrumm:BAAALgAECgQJBQAAAA==.Allesar:BAABLgAECn8cAAICAAcJtxzHAgA5AgACAAcJtxzHAgA5AgAAAA==.Allila:BAABLgAECn8eAAIDAAgJghwpFgAaAgADAAgJghwpFgAaAgAAAA==.Aloreith:BAAALgAECgEJAQAAAA==.Aloysia:BAAALgADCgUJCAAAAA==.',
Am='Ambrozyn:BAAALgAECgkJDwAAAA==.',
An='Andrew:BAAALgAECgYJCgAAAA==.Anik:BAAALgAECgYJBwAAAA==.Animalz:BAAALgADCgYJBgABLgAECgkJFgAEAKoQAA==.Anna:BAABLgAFFH8LAAIDAAUJPBwpEwBNAQADAAUJPBwpEwBNAQAAAA==.Anturoc:BAAALgADCgkJFwAAAA==.',
Ap='Apalrapzz:BAABLgAECn8XAAIDAAYJtQOEXwCaAAADAAYJtQOEXwCaAAABLgAECgkJQwAFAG8GAA==.Apollo:BAAALgADCgEJAQAAAA==.',
Ar='Araphael:BAAALgAECgYJBwAAAA==.Ardrelar:BAABLgAECn8YAAIGAAgJdAswOwBZAQAGAAgJdAswOwBZAQAAAA==.Arekanna:BAAALgAECgMJAwAAAA==.Aroseath:BAAALgADCgMJAwAAAA==.Arthoz:BAAALgADCgIJAgABLgAECggJGQAHAP4RAA==.',
As='Ashog:BAAALgAECgIJAgAAAA==.Astar:BAAALgAECgEJAQABLgAFFAQJDwAIADAcAA==.Astraea:BAABLgAECn9dAAIJAAkJMiDfAADYAgAJAAkJMiDfAADYAgABLgAECgkJVgAHACEjAA==.',
At='Athika:BAAALgAECgEJAQAAAA==.',
Au='Auddorn:BAAALgAECgYJDAAAAA==.Auria:BAABLgAECn8dAAIKAAkJJx3LDACgAgAKAAkJJx3LDACgAgAAAA==.Ausser:BAAALgADCgQJAwAAAA==.',
Ax='Axehand:BAAALgAECgMJBAAAAA==.',
Az='Azarine:BAACLgAFFH8LAAIDAAMJdQt4HABxAAADAAMJdQt4HABxAAAuAAQKfyEAAgMACAnXC0IoAJcBAAMACAnXC0IoAJcBAAAA.Azend:BAAALgAECgIJAgAAAA==.Azphrodite:BAAALgAECgYJBgAAAA==.Azralia:BAABLgAECn8eAAMLAAkJpxXLGgAuAgALAAkJpxXLGgAuAgAMAAEJFg4XaAAsAAAAAA==.',
Ba='Baconator:BAAALgAECgEJAQAAAA==.Barthamus:BAAALgADCgYJBgAAAA==.',
Bb='Bbygee:BAAALgAECgYJEwAAAA==.',
Be='Bearlyshådow:BAAALgADCgUJBQAAAA==.Beastlegion:BAAALgADCgYJFQAAAA==.Beaverboys:BAAALgADCgEJAQAAAA==.Bella:BAAALgAECgcJEwAAAA==.Benjaminadin:BAAALgAECgUJEQAAAA==.Berris:BAAALgADCgYJBgAAAA==.Beyblade:BAAALgAECgQJBQAAAA==.',
Bi='Bigstones:BAAALgADCgYJDAAAAA==.Bimbobanger:BAAALgAECgQJBQAAAA==.',
Bj='Bjorn:BAAALgADCgYJBwAAAA==.',
Bl='Blazinember:BAABLgAECn8+AAINAAkJJAwXBQCMAQANAAkJJAwXBQCMAQAAAA==.Bloodguzzler:BAAALgAECgMJAwAAAA==.Blueberri:BAAALgAECgMJAwAAAA==.',
Bo='Bobbydrac:BAAALgADCgIJAgAAAA==.Boggy:BAABLgAECn8cAAQOAAkJUxcgMgBtAQAOAAcJShQgMgBtAQAIAAcJiwpaKgAfAQAPAAEJsiCEHQBiAAAAAA==.Bolonmixto:BAACLgAFFH8RAAMQAAYJSBwEBABPAQAQAAQJ4B4EBABPAQARAAQJoRs7GgCuAAAuAAQKfyQAAxEACQmZH+MNAMACABEACQkfHuMNAMACABAABAkqGOIRAAcBAAAA.Boop:BAAALgADCgkJCQABLgAECgkJNAAMADkkAA==.Borgin:BAABLgAECn8VAAIEAAYJ3QaVtwDWAAAEAAYJ3QaVtwDWAAAAAA==.Borgofdeth:BAAALgAECgIJAgAAAA==.Borimor:BAABLgAECn8fAAIMAAcJcAxFpgAuAQAMAAcJcAxFpgAuAQABLgAECgkJFgAEAKoQAA==.Bowehunter:BAAALgAECgEJAQAAAA==.',
Br='Braina:BAAALgAECgEJAQAAAA==.Braylia:BAAALgADCggJCAAAAA==.Briaella:BAABLgAECn8eAAMSAAYJwhHJOQAVAQASAAYJwhHJOQAVAQATAAEJuAMHiQAmAAABLgAECgkJQQAUAPocAA==.Bridgetta:BAAALgAECgIJAgAAAA==.Brisli:BAAALgADCgcJBwABLgAECgkJHQAKACcdAA==.Briëlla:BAABLgAECn9BAAQUAAkJ+hyOGQCtAgAUAAkJ+hyOGQCtAgAVAAEJDQjpQAAlAAAWAAEJOgMAbQASAAAAAA==.Bromdrago:BAAALgAECgEJAQAAAA==.Bromkin:BAABLgAECn8ZAAIXAAkJIxuoBQA3AQAXAAkJIxuoBQA3AQAAAA==.',
Bu='Bubonics:BAAALgAECgUJBQAAAA==.',
['Bë']='Bëorn:BAAALgAECgUJBQABLgAECgkJFgAEAKoQAA==.',
Ca='Calindala:BAAALgADCggJBAAAAA==.Calinor:BAABLgAECn8cAAIMAAYJTRNsFQAyAQAMAAYJTRNsFQAyAQAAAA==.Calliopeh:BAAALgAECgQJBQAAAA==.Carl:BAAALgAECgkJEQAAAA==.Case:BAAALgADCgEJAQAAAA==.Castandie:BAABLgAECn8aAAIYAAYJCQeG8AAZAQAYAAYJCQeG8AAZAQAAAA==.',
Ce='Ceran:BAABLgAECn8yAAIZAAkJ6hNDFADvAQAZAAkJ6hNDFADvAQAAAA==.Cereus:BAACLgAFFH8PAAMIAAQJMByuCABJAQAIAAQJMByuCABJAQAPAAIJpwwDCgCHAAAuAAQKf0oAAwgACQkXJPMAAKsDAAgACQkXJPMAAKsDAA8ACQmEHOgCAH4CAAAA.',
Ch='Chaelenge:BAABLgAECn8lAAMLAAkJSh5iCAAFAwALAAkJSh5iCAAFAwAMAAMJpQlLWwFWAAAAAA==.Charles:BAAALgAECgkJAwAAAA==.Cheatt:BAAALgAECgEJAQAAAA==.Chyran:BAABLgAECn8aAAMMAAgJAQzeHAD5AAAMAAgJAQzeHAD5AAALAAIJHRY5bQCBAAAAAA==.',
Cl='Clock:BAAALgAFFAEJAQAAAA==.Cloeh:BAAALgAECgEJAQAAAA==.',
Co='Cocobutters:BAAALgADCgEJAQAAAA==.Coloratura:BAABLgAECn8uAAICAAkJeBlDAwASAgACAAkJeBlDAwASAgAAAA==.Corydh:BAAALgAECgYJEAAAAA==.',
Cp='Cptkanuckles:BAAALgAFFAIJAwAAAA==.',
Cr='Crazyelf:BAAALgADCgQJCAAAAA==.Crimsonmoon:BAAALgAECggJCAABLgAECgkJNAAMADkkAA==.Crunchbar:BAAALgADCgUJBQAAAA==.',
Cu='Cubscout:BAAALgADCgcJBwAAAA==.Cutecop:BAAALgAECgIJBAAAAA==.',
['Có']='Cóffee:BAAALgADCgkJCQAAAA==.',
Da='Dagast:BAAALgADCgYJCQAAAA==.Dagethon:BAAALgAECgIJAQAAAA==.Dalielah:BAAALgAECgUJCAAAAA==.Danfortesque:BAAALgADCgIJAgAAAA==.Darkkstarr:BAAALgAECgUJBwAAAA==.Daromiciah:BAAALgAECgIJAgAAAA==.',
De='Deathnome:BAAALgADCgYJAwAAAA==.Demdots:BAAALgADCgEJAQAAAA==.Denvoker:BAABLgAECn8VAAQIAAgJBg4dHwD+AAAIAAYJrAodHwD+AAAOAAMJ5gVMGQBDAAAPAAEJAADhLwAAAAAAAA==.Deputyfluff:BAAALgADCgEJAQAAAA==.Derathull:BAAALgAECgQJBAAAAA==.Desmac:BAAALgAECgYJBgABLgAFFAIJAgABAAAAAA==.',
Dh='Dhjacob:BAAALgAECgYJEQAAAA==.',
Di='Diddykong:BAAALgAECgkJCQAAAA==.Dirtnapp:BAAALgADCgEJAgAAAA==.',
Do='Docqt:BAAALgADCgEJAQAAAA==.Dolleez:BAAALgAECgcJCAAAAA==.Doodridder:BAAALgAECgQJBAAAAA==.Dooman:BAAALgADCgcJDAAAAA==.Dotpockets:BAAALgAECgUJBQAAAA==.Dotsenpai:BAAALgADCgQJBQAAAA==.Doubtfire:BAABLgAECn9DAAMFAAkJbwZADwDMAAAFAAkJbwZADwDMAAAaAAIJiAE6+AAbAAAAAA==.',
Dr='Dragii:BAAALgAECgMJBAAAAA==.',
Du='Dunkaroo:BAABLgAECn8eAAIbAAkJMhQFRAC8AQAbAAkJMhQFRAC8AQAAAA==.',
['Dé']='Dékü:BAAALgAECgcJCgAAAA==.',
Ei='Eikinskaldi:BAAALgAECgEJAgAAAA==.',
El='Elcarly:BAAALgAECgEJAgAAAA==.Eleridus:BAAALgADCgMJAwAAAA==.Elphysa:BAAALgADCgQJBAAAAA==.',
Em='Empty:BAABLgAECn8mAAIMAAkJ5gzsdgCAAQAMAAkJ5gzsdgCAAQAAAA==.',
En='Endormu:BAAALgAECgIJAgAAAA==.',
Ep='Epiduralrot:BAACLgAFFH8SAAQcAAYJbBPZDQDGAAAcAAQJLAjZDQDGAAAdAAMJYhBYhAC9AAAeAAIJlyBVDwCYAAAuAAQKfycABB0ACAnCILguAFICAB0ACAlCHbguAFICABwABAn1GWAiAEMBAB4AAwlJIsUSAAABAAAA.',
Er='Eraessyr:BAAALgAECgQJBAAAAA==.Erind:BAAALgADCgcJBwAAAA==.',
Et='Etërnal:BAAALgADCgkJDwAAAA==.',
Fa='Fabiand:BAAALgAECgIJAgAAAA==.Faithful:BAAALgAECgkJBwAAAA==.Faithfulness:BAAALgAECgEJAQAAAA==.Faiye:BAAALgAECggJCgAAAA==.Fandris:BAAALgAECgEJAQAAAA==.',
Fe='Feldrus:BAAALgAECgMJBAABLgAECgkJRwAfAOEVAA==.Fendre:BAAALgADCgEJAQAAAA==.',
Fl='Flaregun:BAAALgAECgIJAwABLgAECgkJEQABAAAAAA==.',
Fo='Forsëti:BAAALgAECgIJAgAAAA==.',
Fr='Freakadeek:BAAALgAECgMJBAABLgAECgkJFQAVAGsNAA==.Frierenn:BAABLgAECn8oAAIYAAkJ1hNMUwDjAQAYAAkJ1hNMUwDjAQAAAA==.Frosh:BAABLgAECn8ZAAMHAAgJ/hF2OACgAQAHAAgJ/hF2OACgAQAgAAMJ4h2/bQCMAAAAAA==.',
Fu='Fuegaluna:BAAALgADCgkJCwAAAA==.Fundetected:BAACLgAFFH8IAAIbAAMJOA2nbQCvAAAbAAMJOA2nbQCvAAAuAAQKfywAAhsACQmYHJYeAF0CABsACQmYHJYeAF0CAAAA.',
['Fâ']='Fâllenboy:BAAALgAECgMJAwAAAA==.',
Ga='Garross:BAAALgADCgYJCAAAAA==.',
Ge='Geoffrii:BAAALgADCgcJBwAAAA==.',
Gh='Ghouldottie:BAAALgAECgMJAwAAAA==.',
Gi='Gilidar:BAABLgAECn8xAAMhAAkJ1yTkAgARAwAhAAkJ/yPkAgARAwAGAAYJ2yNsNAB5AQAAAA==.Gillarria:BAABLgAECn8UAAMiAAYJoRDaAgBTAQAiAAYJoRDaAgBTAQAZAAEJnAi/eQAmAAAAAA==.',
Gn='Gnomerdenis:BAAALgADCgUJBgAAAA==.',
Go='Goochiemon:BAAALgAECgQJBAAAAA==.Gotalight:BAAALgAECgcJCAAAAA==.',
Gr='Gravecrawler:BAAALgAECgYJBQAAAA==.Grimmberly:BAAALgAECgcJDAABLgAECgkJGgAJACMcAA==.Grimmothy:BAABLgAECn8sAAISAAkJ3BafEgAfAgASAAkJ3BafEgAfAgABLgAECgkJGgAJACMcAA==.Grimoire:BAABLgAECn8aAAIJAAkJIxxGAQCHAgAJAAkJIxxGAQCHAgAAAA==.Grindr:BAAALgAECgIJAgAAAA==.',
Gu='Guanyin:BAAALgAECgEJAQAAAA==.Gutdrunel:BAAALgAECgMJAwAAAA==.Guthumwar:BAAALgAECgYJCAAAAA==.Guthunnel:BAABLgAECn86AAIEAAkJvhIgOgD2AQAEAAkJvhIgOgD2AQAAAA==.Gutshadra:BAAALgAECgcJBgAAAA==.',
['Gö']='Göldenvenom:BAAALgADCgQJBAAAAA==.',
Ha='Haides:BAAALgAECgIJAgAAAA==.Hakuri:BAAALgADCgcJDwABLgAECgYJDQABAAAAAA==.Hannibow:BAAALgAECgcJCAAAAA==.Happydru:BAAALgADCgcJDgAAAA==.Havic:BAAALgADCgYJBgAAAA==.Hazuki:BAAALgAECgEJAgAAAA==.',
He='Helle:BAABLgAECn8gAAQfAAkJuxRaHQAuAgAfAAkJuxRaHQAuAgASAAYJ6Aj0TQALAQATAAIJ7g8sFgBdAAAAAA==.Hellgrim:BAAALgADCgEJAQABLgAECgkJGgAJACMcAA==.',
Hi='Highfever:BAABLgAECn8UAAIaAAUJ3A32cADiAAAaAAUJ3A32cADiAAAAAA==.',
Ho='Hoawatt:BAAALgAECgQJBQAAAA==.Holynova:BAAALgADCgQJBwABLgAECgQJBAABAAAAAA==.Hoofkick:BAAALgAECgIJAgAAAA==.',
Hr='Hrum:BAAALgADCgEJAQAAAA==.',
Hu='Hubbaroo:BAAALgADCgQJBAABLgAECgkJMwAaAIIbAA==.Huuch:BAABLgAECn8oAAIEAAkJEAs4VgChAQAEAAkJEAs4VgChAQAAAA==.',
Hy='Hycinari:BAAALgAECgIJAgAAAA==.Hyperius:BAAALgAECgUJBQAAAA==.',
Ic='Icrucify:BAACLgAFFH8FAAIEAAMJ6RwlFQCwAAAEAAMJ6RwlFQCwAAAuAAQKfzkAAgQACQmgJUQIABkDAAQACQmgJUQIABkDAAAA.',
Ig='Ignee:BAABLgAFFH8IAAMjAAMJRBPfFQB0AAAGAAMJpAT/PgCsAAAjAAIJnBjfFQB0AAAAAA==.Ignia:BAAALgAECgIJAgABLgAECggJCgABAAAAAA==.',
Il='Ilanos:BAAALgAECgIJAgAAAA==.',
Im='Imeria:BAAALgAECgQJBgAAAA==.Imissmobo:BAAALgADCgIJAgAAAA==.',
In='Inhyai:BAAALgAECgMJAwABLgAFFAQJBAABAAAAAA==.',
Ir='Iremoon:BAABLgAECn88AAMUAAkJkxWwNgAkAgAUAAkJkxWwNgAkAgAWAAIJRwQTQgBCAAABLgAFFAMJCwAMADgMAA==.Iridio:BAAALgAECgYJBgAAAA==.',
Ja='Jadexx:BAAALgAECgMJAwAAAA==.Jaeler:BAAALgAECggJDgAAAA==.',
Je='Jedistang:BAAALgAECgQJBgAAAA==.Jestyr:BAACLgAFFH8RAAMZAAQJaRgiDgA1AQAZAAQJaRgiDgA1AQAiAAIJAxUUBwCEAAAuAAQKfxYAAxkACQlUH2IGANECABkACQlUH2IGANECABsAAQmBB28oASUAAAAA.Jestyrd:BAAALgAECgMJAwABLgAFFAQJEQAZAGkYAA==.Jestyrdk:BAABLgAECn8UAAIUAAgJrR9fBAB2AgAUAAgJrR9fBAB2AgABLgAFFAQJEQAZAGkYAA==.Jestyrmo:BAABLgAECn8rAAMSAAgJARtiJQCDAQASAAcJ2BliJQCDAQAfAAgJgBCxRABZAQABLgAFFAQJEQAZAGkYAA==.',
Ji='Jitjitjitjit:BAAALgAECgEJAQAAAA==.Jiyao:BAACLgAFFH8eAAITAAQJ4R/yCwBmAQATAAQJ4R/yCwBmAQAuAAQKf0wAAxMACQnwJKgCAEADABMACQnwJKgCAEADAB8AAQmeB+tsACgAAAAA.',
Jo='Jodi:BAAALgAECgYJEwAAAA==.',
Ju='Jules:BAAALgAFFAIJAgAAAA==.Jumbo:BAAALgAECgMJBAABLgAECgQJBQABAAAAAA==.',
Ka='Kaceya:BAAALgAECgUJDQAAAA==.Kainarasa:BAAALgAECgYJEwABLgAECgkJNAAMADkkAA==.Kairn:BAAALgADCggJDAAAAA==.Kairnei:BAAALgADCgYJEgAAAA==.Katarinea:BAABLgAECn8fAAIFAAkJiw7DKgB/AQAFAAkJiw7DKgB/AQAAAA==.Kaypop:BAAALgAECgcJEwAAAA==.',
Ke='Keats:BAAALgAECgIJAgAAAA==.Keeytz:BAAALgADCgYJAgAAAA==.',
Kh='Khalessie:BAABLgAECn8lAAIKAAkJOQ3PIwCwAQAKAAkJOQ3PIwCwAQAAAA==.Kheldar:BAAALgAECgkJAwAAAA==.Khrone:BAAALgAECgEJAgAAAA==.',
Ki='Kirsi:BAABLgAECn8kAAMkAAkJpB5LCABBAgAkAAkJpB5LCABBAgAHAAEJeQHi9gAZAAAAAA==.Kiselle:BAAALgAECgQJBAABLgAECgkJHQAKACcdAA==.',
Kl='Klorick:BAAALgAECgYJBgABLgAECgkJFgAEAKoQAA==.',
Ko='Koonu:BAABLgAFFH8FAAILAAMJ/RJDFQC1AAALAAMJ/RJDFQC1AAAAAA==.Korkneelious:BAAALgAECgYJDAAAAA==.',
Kr='Kretor:BAAALgAECgQJDgABLgAFFAMJBQALAP0SAA==.',
Ku='Kungfudru:BAAALgAECgEJAQAAAA==.',
Kw='Kwai:BAAALgAECgYJBgABLgAECgkJFgAEAKoQAA==.',
Ky='Kyomu:BAAALgAECgcJBwABLgAECgkJNAAMADkkAA==.',
La='Lavendarmoon:BAAALgAECgEJAQAAAA==.',
Li='Lillock:BAAALgAECgIJAgAAAA==.Lineofsight:BAABLgAECn9QAAIGAAgJzh2bAgBNAgAGAAgJzh2bAgBNAgAAAA==.Liths:BAABLgAECn87AAIiAAkJlAlIEQA4AQAiAAkJlAlIEQA4AQAAAA==.Littlemoses:BAABLgAECn8nAAIEAAkJiRsuLwAgAgAEAAkJiRsuLwAgAgAAAA==.',
Lo='Lockdarkly:BAAALgAECgUJCQAAAA==.Lono:BAAALgADCgQJBwAAAA==.Lostdru:BAAALgADCgEJAgAAAA==.',
Lu='Lululuvely:BAABLgAECn8VAAMKAAYJIxV5KQCIAQAKAAYJIxV5KQCIAQACAAUJZwk5UwDqAAAAAA==.Lulzimadrood:BAAALgADCgMJAwAAAA==.',
Ma='Machrona:BAAALgAECgEJAQAAAA==.Magejacob:BAAALgADCgcJCQABLgAECgYJEQABAAAAAA==.Malendren:BAAALgAECgEJAQAAAA==.Malignus:BAACLgAFFH8HAAIYAAQJdRDXLQAWAQAYAAQJdRDXLQAWAQAuAAQKfz8AAhgACQk3IR8DAOACABgACQk3IR8DAOACAAEuAAMKCQkXAAEAAAAA.Malthaos:BAAALgADCgQJBAABLgAECgkJJwAYAAIdAA==.Maneyen:BAAALgADCgQJAwAAAA==.Margot:BAAALgAECgYJEgAAAA==.Marksmann:BAAALgAECgIJBQAAAA==.Marriah:BAAALgAECgQJBAABLgAECgkJJwAEAIkbAA==.Mavane:BAAALgADCgUJAQAAAA==.Mawhriccio:BAAALgAECgEJAQAAAA==.',
Mc='Mcdavé:BAABLgAECn88AAIgAAkJyxCNJwCwAQAgAAkJyxCNJwCwAQAAAA==.',
Me='Meathshield:BAAALgADCgMJAwABLgAECggJHgADAIIcAA==.Meerclar:BAAALgAECgIJAwABLgAECggJDwABAAAAAA==.Melaila:BAABLgAECn9WAAIHAAkJISNaAgDMAgAHAAkJISNaAgDMAgAAAA==.Mellwynn:BAAALgAECgUJDwAAAA==.Melunaura:BAAALgAECggJCQABLgAECgkJVgAHACEjAA==.Menalaus:BAAALgAECgUJBQAAAA==.',
Mf='Mf:BAABLgAECn8hAAIbAAcJtxRaaABVAQAbAAcJtxRaaABVAQAAAA==.',
Mi='Micheal:BAAALgAFFAIJAgAAAA==.Midir:BAAALgAECgQJBAAAAA==.Miladrayn:BAAALgADCgcJFgAAAA==.Mimikyu:BAAALgAFFAEJAQABLgAFFAcJIAAgAJwdAA==.Min:BAAALgAECgIJAgAAAA==.Mistwallker:BAAALgADCgUJBQAAAA==.Miñitañk:BAAALgAECgIJAgAAAA==.',
Mo='Moardotz:BAAALgADCgUJBgAAAA==.Moldthinur:BAABLgAECn84AAIXAAkJbSVZAAA2AwAXAAkJbSVZAAA2AwAAAA==.Mongrol:BAAALgAECgQJBgAAAA==.Monju:BAAALgAECgEJAQAAAA==.Monôpolyguy:BAAALgAECgIJAgAAAA==.Moonowl:BAAALgAECgQJBgAAAA==.Mordrack:BAAALgAECgYJBgAAAA==.Moreganna:BAAALgADCgYJCQABLgAECgUJFAAaANwNAA==.',
Mu='Mummrakhan:BAABLgAECn8dAAIdAAkJHgWlpgD0AAAdAAkJHgWlpgD0AAAAAA==.Murraya:BAAALgADCgcJBwAAAA==.',
Na='Nagasaki:BAAALgAECgkJDQABLgAECgkJEQABAAAAAA==.Naniel:BAACLgAFFH8ZAAIGAAUJ2g6CJQAfAQAGAAUJ2g6CJQAfAQAuAAQKfy0AAwYACQmLGMMdAAACAAYACQmDFsMdAAACACMABAneG3cFADkBAAAA.Narmaya:BAAALgADCgMJAwAAAA==.',
Ne='Neat:BAAALgAECgcJBwABLgAFFAMJBAABAAAAAA==.Neb:BAACLgAFFH8TAAIdAAQJ/g8qKwDcAAAdAAQJ/g8qKwDcAAAuAAQKf0oAAx0ACQnHHJUYAJACAB0ACQnHHJUYAJACABwAAgm5EVZXAGgAAAAA.Necroy:BAABLgAECn8VAAIcAAkJCh6rAgCHAgAcAAkJCh6rAgCHAgAAAA==.Netheris:BAAALgAECgEJAQAAAA==.',
Ni='Niccee:BAABLgAECn8iAAIFAAkJrwwgKwB8AQAFAAkJrwwgKwB8AQAAAA==.Nick:BAACLgAFFH8RAAIdAAUJ+BuIEQBYAQAdAAUJ+BuIEQBYAQAuAAQKfxgAAx0ACAkYIykbALECAB0ACAkYIykbALECABwAAQkAAHuAABAAAAAA.Nightflurry:BAAALgAECgcJEgAAAA==.Nightslife:BAAALgADCgUJBQABLgADCgUJBQABAAAAAA==.',
No='Noodles:BAAALgAECgcJEgABLgAECggJIgAbAH0WAA==.Nosebleeds:BAABLgAECn8VAAMJAAgJCh3nEADcAQAJAAcJdxznEADcAQAlAAIJfxw8RQBRAAAAAA==.Notyourheals:BAABLgAECn8wAAMgAAgJ2BEIMgB1AQAgAAgJ2BEIMgB1AQAHAAQJSAGjjQBfAAAAAA==.',
Oa='Oakay:BAAALgAECgMJAwAAAA==.',
Ob='Obee:BAABLgAECn8nAAIaAAkJNxZAKgADAgAaAAkJNxZAKgADAgAAAA==.',
Od='Odette:BAAALgADCgYJBgAAAA==.Odsum:BAABLgAECn8XAAIMAAYJWBpciwBaAQAMAAYJWBpciwBaAQAAAA==.',
Om='Ombo:BAAALgAECgMJAwAAAA==.Omegasupreme:BAAALgAECgIJAgAAAA==.',
Oo='Oogrutamu:BAAALgAECgIJAgAAAA==.',
Or='Orionna:BAAALgADCggJBAAAAA==.',
Pa='Pal:BAAALgAECgEJAQAAAA==.Palanious:BAAALgAECgMJBgAAAA==.Pandabear:BAAALgADCgkJDwAAAA==.Papamidnight:BAAALgAECgIJAwAAAA==.Papasmurff:BAAALgADCgIJAgAAAA==.Papichulo:BAAALgAECgIJAgAAAA==.',
Pe='Percival:BAABLgAECn8mAAIMAAkJUA2bbgCRAQAMAAkJUA2bbgCRAQAAAA==.',
Pi='Pinheadjerry:BAAALgAECgEJAQAAAA==.Pinhêadlarry:BAAALgADCgYJBgAAAA==.Pizzaslice:BAABLgAECn80AAIMAAkJOSRIBgA/AwAMAAkJOSRIBgA/AwAAAA==.',
Po='Poetbrat:BAAALgADCgkJIQABLgAECgkJQwAFAG8GAA==.Porkles:BAAALgADCgQJBQAAAA==.',
Pr='Praxiscannon:BAAALgAECgUJBgAAAA==.Prettydead:BAAALgADCgIJAgAAAA==.',
Pu='Pumpshire:BAABLgAECn8jAAIPAAkJswsyCgB9AQAPAAkJswsyCgB9AQAAAA==.',
Pw='Pwnstar:BAAALgADCgMJAwABLgAECgkJFQAVAGsNAA==.Pwongo:BAACLgAFFH8PAAIaAAQJBx2dDQBTAQAaAAQJBx2dDQBTAQAuAAQKf0MAAxoACAnUIGgBAO4CABoACAnUIGgBAO4CAAUAAgkgAqCqABMAAAAA.',
Qu='Queue:BAABLgAECn8jAAIcAAYJLBWwBAAmAQAcAAYJLBWwBAAmAQAAAA==.Quilten:BAABLgAECn8cAAITAAcJuA08OwAUAQATAAcJuA08OwAUAQAAAA==.',
Ra='Raenii:BAAALgAFFAEJAwABLgAFFAIJBgACAMMSAA==.Ramoth:BAABLgAECn8VAAIgAAgJrQcNZAC5AAAgAAgJrQcNZAC5AAAAAA==.Ranoe:BAAALgADCgcJDQAAAA==.Rapids:BAAALgADCgYJCAAAAA==.Rashamka:BAAALgAECgIJAgAAAA==.Rasputan:BAAALgAECgEJAQAAAA==.Rayne:BAABLgAECn8nAAIYAAkJAh0gLwBcAgAYAAkJAh0gLwBcAgAAAA==.Razelda:BAAALgAECgkJCAAAAA==.',
Re='Reolz:BAAALgADCgUJBAAAAA==.Reveya:BAABLgAECn8pAAMVAAkJJRbJAQAQAgAVAAkJJRbJAQAQAgAUAAcJng6wpQAjAQAAAA==.',
Ri='Rinnian:BAAALgAECgYJDwAAAA==.Rinny:BAAALgAECgEJAQAAAA==.Riptideaf:BAAALgAECgEJAQAAAA==.',
Ro='Roadwanderer:BAAALgAECgcJEgAAAA==.Robbiedrake:BAAALgAECgEJAQABLgAFFAQJBwATAGMNAA==.Robbiemonk:BAACLgAFFH8HAAMTAAQJYw02GwBUAAATAAQJGQc2GwBUAAASAAIJXBJiIQA/AAAuAAQKf0gAAxIACQlTG1cMAHACABIACQlTG1cMAHACABMABAn3AxNeAJgAAAAA.Robbiesboomy:BAAALgAECgIJAgABLgAFFAQJBwATAGMNAA==.Rodric:BAAALgAECgUJBQABLgAECgkJFgAEAKoQAA==.Rokage:BAAALgADCgYJCwAAAA==.',
Ru='Runed:BAAALgAECgYJCQAAAA==.Runetottem:BAAALgADCgEJAQAAAA==.',
Rx='Rxeight:BAAALgAECgYJBgAAAA==.',
Sa='Sakura:BAAALgAECgcJDwAAAA==.Sannith:BAABLgAECn86AAIYAAkJUxasOQAyAgAYAAkJUxasOQAyAgAAAA==.Sapphi:BAABLgAECn8lAAIXAAkJew/PFACEAQAXAAkJew/PFACEAQAAAA==.Sarjarus:BAAALgADCgYJAgAAAA==.',
Se='Seespottank:BAABLgAECn8lAAIhAAkJ2BH6AgCQAQAhAAkJ2BH6AgCQAQAAAA==.Senjinbenjin:BAAALgAECgQJBQAAAA==.',
Sh='Shadowallker:BAAALgADCgMJAwABLgADCgUJBQABAAAAAA==.Shadowlich:BAAALgAECgYJBgAAAA==.Shakjabuti:BAAALgADCgUJBQAAAA==.Shamanoodles:BAAALgAECgkJEQABLgAECgkJVgAHACEjAA==.Sharma:BAAALgAECgcJBwABLgAFFAMJBQALAP0SAA==.Shattersun:BAAALgAECgQJAgAAAA==.Shauralin:BAAALgAECgEJAQAAAA==.Shelbei:BAAALgAECgQJBgAAAA==.Shespawn:BAAALgAFFAIJBAAAAA==.Shoukkan:BAAALgADCgcJBwAAAA==.Shurie:BAABLgAECn8WAAMEAAkJqhDkLwDxAQAEAAkJqhDkLwDxAQAmAAEJLQJiMgApAAAAAA==.Shykara:BAAALgADCgcJGAABLgAECggJFQAgAK0HAA==.Shâdê:BAAALgAECgEJBAAAAA==.Shådowblade:BAAALgADCgkJCQAAAA==.',
Si='Sinae:BAAALgAECgEJAQAAAA==.Sindrak:BAAALgAECgEJAgAAAA==.Sins:BAAALgAECgIJAgAAAA==.Sinsorain:BAAALgADCgEJAQAAAA==.Sipsy:BAAALgAECgcJBQAAAA==.',
Sk='Skulcrack:BAAALgADCgcJDgAAAA==.',
Sl='Slabomeat:BAAALgAECgcJBwABLgAECgkJFgAEAKoQAA==.Slipperybop:BAACLgAFFH8PAAIMAAMJ4CT7QAApAQAMAAMJ4CT7QAApAQAuAAQKfxwAAgwACQlgI/sJABcDAAwACQlgI/sJABcDAAEuAAUUAQkDAAEAAAAA.Slugbow:BAAALgAECgYJCQAAAA==.',
Sm='Smashed:BAAALgAFFAIJAgABLgAFFAIJAgABAAAAAA==.',
Sn='Snakeshadow:BAAALgAECgMJAwAAAA==.Snoom:BAABLgAECn8kAAIHAAkJZAYVcQAJAQAHAAkJZAYVcQAJAQAAAA==.',
So='Soldanis:BAAALgAFFAEJAgAAAA==.Sorena:BAAALgAECgMJAwAAAA==.',
Sp='Spawny:BAAALgADCgYJBgAAAA==.Spazoff:BAAALgAECgUJDQAAAA==.Spyman:BAAALgAECgEJBAAAAA==.Spyro:BAAALgAECgMJAwAAAA==.',
Sr='Srhubbabubba:BAABLgAECn8zAAIaAAkJghv7EQC/AgAaAAkJghv7EQC/AgAAAA==.',
St='Starz:BAAALgADCgkJCQAAAA==.Staticbdk:BAAALgAECgEJAQABLgAFFAQJBAABAAAAAA==.Statickling:BAAALgAFFAQJBAAAAA==.Steamynix:BAAALgADCgUJBQAAAA==.Sternn:BAAALgAECgEJAgAAAA==.Steviathan:BAAALgAECgYJDAAAAA==.Straif:BAAALgAECgQJBwAAAA==.',
Sv='Sveliaa:BAAALgAECgIJAgABLgAFFAQJBAABAAAAAA==.',
Sw='Sweetest:BAAALgAECgYJBwAAAA==.Swolman:BAAALgADCgYJBgAAAA==.',
Sy='Sydeon:BAAALgAECgYJEQAAAA==.Syndra:BAAALgAECgEJAQABLgAECggJCgABAAAAAA==.',
Ta='Tanderina:BAAALgAECgIJAgAAAA==.Tankshock:BAABLgAFFH8FAAIjAAIJTQIHHABIAAAjAAIJTQIHHABIAAAAAA==.Taylor:BAAALgAECgcJAgABLgAFFAUJCwADADwcAA==.',
Te='Teddy:BAAALgAECgMJBAAAAA==.Tellah:BAABLgAECn8ZAAMHAAkJtxk7FwCPAgAHAAkJtxk7FwCPAgAgAAUJ/wk5YwC2AAABLgAFFAMJBQALAP0SAA==.Tellairion:BAAALgADCgYJCQAAAA==.',
Th='Thegodofwar:BAAALgADCggJCQAAAA==.Thegreatland:BAAALgAECgMJAwAAAA==.Theiren:BAAALgAECgEJAQAAAA==.Themuffinman:BAAALgAECgkJEQABLgAECgkJNAAMADkkAA==.',
To='Tongari:BAAALgADCgQJBAAAAA==.',
Tu='Tullinnelor:BAAALgADCgEJAQABLgAECgkJGwACABwRAA==.',
Tw='Twomz:BAACLgAFFH8IAAIHAAMJ/gZwNwBtAAAHAAMJ/gZwNwBtAAAuAAQKfzUAAwcACQkdEX8uAPwBAAcACQkdEX8uAPwBACAABQlQDRMTAK8AAAAA.',
Um='Umi:BAAALgAECgEJAQABLgAFFAMJBwAHAOMVAA==.',
Un='Unclebenjin:BAAALgAECgYJBgAAAA==.Unkadier:BAAALgADCgMJAwABLgAECgkJFwAYAA0hAA==.',
Va='Varkbyte:BAAALgAECgMJAwAAAA==.Varock:BAAALgAECgcJBwABLgAECgkJNAAMADkkAA==.Varrieto:BAAALgAECgcJBwAAAA==.Vavaboom:BAAALgADCggJCAAAAA==.',
Ve='Veirlyn:BAAALgAECgkJCQAAAA==.',
Vi='Vindication:BAABLgAECn8jAAILAAgJ9iJ8BwAUAwALAAgJ9iJ8BwAUAwAAAA==.Viz:BAAALgADCgkJIQAAAA==.',
Vo='Voidshådow:BAABLgAECn8XAAIbAAcJmxOBXwBrAQAbAAcJmxOBXwBrAQAAAA==.Voreho:BAAALgADCggJCAAAAA==.',
Vr='Vraul:BAAALgAECgMJAgABLgAECgkJJwAYAAIdAA==.',
Vu='Vulpain:BAABLgAECn8XAAIHAAkJPxo3AwCMAgAHAAkJPxo3AwCMAgABLgAECgkJNAAMADkkAA==.',
Vy='Vylandra:BAAALgAECgQJBQAAAA==.',
We='Weepingwillo:BAAALgAECgQJBAAAAA==.Wennon:BAAALgADCgQJBAAAAA==.',
Wh='Whatsituya:BAAALgADCgcJCwAAAA==.Where:BAAALgAECgUJCgABLgAECgkJEQABAAAAAA==.Whiteangel:BAAALgAECgEJAQAAAA==.',
Wi='Willythewolf:BAAALgADCgEJAQAAAA==.Willywallace:BAAALgAECggJCQAAAA==.Wiseman:BAAALgAECgMJAwAAAA==.',
Wo='Wolfowl:BAABLgAECn8XAAIFAAUJXQdrGABrAAAFAAUJXQdrGABrAAAAAA==.',
Xa='Xaela:BAABLgAECn8dAAIbAAkJEhcYOQDiAQAbAAkJEhcYOQDiAQAAAA==.Xantriar:BAAALgADCgUJBQAAAA==.Xarbariste:BAAALgAECggJDwAAAA==.Xarous:BAAALgAECgkJCQABLgAECgkJNAAMADkkAA==.',
Xe='Xeon:BAAALgAECgUJDQAAAA==.',
Xi='Xiabal:BAACLgAFFH8IAAMFAAMJYhSqFgDOAAAFAAMJYhSqFgDOAAAaAAIJ4QltJwBTAAAuAAQKfy4AAxoACQnTHlIJACQDABoACQnTHlIJACQDAAUABAmQG8UMAO4AAAAA.',
Xw='Xweakling:BAAALgAECgcJDAABLgAFFAQJEAAGAEobAA==.Xweekling:BAACLgAFFH8QAAIGAAQJShu8GQBLAQAGAAQJShu8GQBLAQAuAAQKfy4AAgYACQnyIyMDADsDAAYACQnyIyMDADsDAAAA.Xweeklingdh:BAAALgAECgYJBgABLgAFFAQJEAAGAEobAA==.',
Xy='Xynoria:BAAALgAECgEJAQAAAA==.',
Ye='Yendara:BAAALgAECgEJAQAAAA==.Yetihunter:BAAALgADCgMJBAAAAA==.',
Yu='Yuxiong:BAAALgADCgkJIAAAAA==.',
Za='Zaraeth:BAAALgAECgUJDAABLgAECggJDwABAAAAAA==.',
Ze='Zedra:BAAALgAECgQJEgABLgAECgYJEwABAAAAAA==.Zenhubba:BAAALgAECgYJBgABLgAECgkJMwAaAIIbAA==.Zerostar:BAABLgAECn8XAAImAAcJshEHLQA9AQAmAAcJshEHLQA9AQABLgAECgkJNAAEAIEfAA==.Zevon:BAAALgAECgIJAgABLgAECggJDwABAAAAAA==.',
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
