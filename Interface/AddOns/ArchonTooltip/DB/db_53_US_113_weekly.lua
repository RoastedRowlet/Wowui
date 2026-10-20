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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Druid-Guardian','Warlock-Destruction','Unknown-Unknown','Druid-Restoration','Priest-Holy','Shaman-Restoration','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Druid-Balance','Paladin-Holy','Warrior-Protection','Evoker-Preservation','Mage-Frost','Hunter-BeastMastery','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Evoker-Devastation','DemonHunter-Havoc','Warrior-Arms','DemonHunter-Vengeance','Priest-Shadow','Hunter-Marksmanship','Monk-Mistweaver','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Aberration:BAAANQADCgUIBQAAAA==.',
Ad='Addely:BAABNQAECn8WAAIBAAcKrg7W+wCVAQABAAcKrg7W+wCVAQAAAA==.Addly:BAAANQADCgcIBwAAAA==.Adelybeast:BAAANQADCgcJBwAAAA==.Adelyden:BAAANQADCgMIAwAAAA==.Adonysroth:BAAANQAECgYIEQAAAA==.',
Ae='Aellyndsonis:BAAANQAECgIIAwAAAA==.',
Ak='Akaika:BAAANQADCgcIBwAAAA==.Aksala:BAAANQABCgIIAgAAAA==.',
Al='Alaralia:BAAANQAECggIEwABNQAFFAcIEwACAAsgAA==.Alarathel:BAAANQADCggICAABNQAFFAcIEwACAAsgAA==.Aleion:BAAANQADCgUIBQABNQAECggIGwADABsSAA==.Alyssandra:BAABNQAECn8UAAIEAAcKWw/7HgB3AQAEAAcKWw/7HgB3AQAAAA==.',
Am='Amarella:BAAANQADCggICAAAAA==.Amarrite:BAAANQADCggIEQAAAA==.Ammalane:BAAANQADCgQIBQABNQADCggIEQAFAAAAAA==.',
An='Anabelli:BAAANQAECgEIAQAAAA==.Angler:BAAANQADCgIIAQAAAA==.',
Ap='Apollyon:BAAANQAECggIEQAAAA==.',
Ar='Arangarr:BAABNQAECn8zAAIGAAoK2B2eAgCdAgAGAAoK2B2eAgCdAgAAAA==.Arcanu:BAAANQAECgMIBAAAAA==.Aresiuz:BAABNQAECn8YAAIHAAkKwxHcZwDnAQAHAAkKwxHcZwDnAQABNQAFFAYIEgAIAK0KAA==.Areyana:BAAANQAECgUICQAAAA==.Ariolas:BAAANQADCgYIBgAAAA==.Arkandra:BAAANQAECgQIBwAAAA==.Arrietty:BAAANQAECgMIEAAAAA==.Arthâs:BAAANQAECgEIAQAAAA==.Arumathe:BAABNQAECn8UAAMJAAkKDAmlDQAqAQAJAAkKDAmlDQAqAQAKAAYK+AaWHQHuAAAAAA==.',
As='Asmodea:BAAANQAECgEIAQAAAA==.',
At='Atlasfall:BAAANQAECgUICwAAAA==.',
Az='Azeriall:BAABNQAECn83AAILAAoKGBcVCADlAQALAAoKGBcVCADlAQAAAA==.Azerodru:BAAANQADCgEIAQAAAA==.',
Ba='Bacnfen:BAABNQAECn8UAAILAAcK2wlDmgBjAQALAAcK2wlDmgBjAQAAAA==.Baconhammr:BAAANQAECgEIAQAAAA==.Badazmf:BAAANQADCgEIAQABNQADCggIFAAFAAAAAA==.Banshiï:BAAANQAECgYIEQAAAA==.Baratheøn:BAABNQAECn8VAAMGAAcKpRS3FgANAQAGAAcKpRS3FgANAQAMAAEK2gLhWAAkAAAAAA==.Bason:BAAANQAECgUIBQAAAA==.',
Be='Beeftard:BAABNQAECn8eAAINAAkKnRodNgCLAgANAAkKnRodNgCLAgAAAA==.',
Bi='Bifficus:BAAANQAECgEIAgAAAA==.Bippity:BAAANQAECgQICQAAAA==.Bivon:BAAANQAECgEIAwAAAA==.',
Bl='Blackfyre:BAAANQAECgEIAQAAAA==.Blackscorn:BAAANQAECgEIAQAAAA==.Bloodopal:BAAANQADCgYICgAAAA==.Blóðdrekkr:BAAANQAECgcIDQAAAA==.',
Bo='Bobbyg:BAAANQABCgYICwAAAA==.Bollace:BAAANQADCgUIBQABNQADCgcIBwAFAAAAAA==.',
By='Byzantium:BAABNQAECn8bAAIOAAcK6AZdJwAFAQAOAAcK6AZdJwAFAQAAAA==.',
['Bô']='Bônebeard:BAAANQAECgYICQAAAA==.',
Ca='Caluu:BAAANQAECgUIDAAAAA==.Cannoli:BAAANQADCgEIAQAAAA==.',
Ce='Celidora:BAAANQADCgcICQABNQAFFAYIDwAPAK4SAA==.',
Ch='Chromatic:BAAANQAECgMIAwAAAA==.Chronic:BAAANQAECgIIAgABNQAECgoKJgAKAB4UAA==.',
Ci='Cinderflamez:BAAANQAECgEIAQAAAA==.',
Co='Coffeeblak:BAAANQADCgYICAABNQADCggICAAFAAAAAA==.Coldstorm:BAABNQAECn8gAAIQAAkK4A44DAD4AQAQAAkK4A44DAD4AQAAAA==.Corrine:BAAANQADCggICAAAAA==.',
Cr='Cristalwolf:BAAANQABCgEJAQAAAA==.',
Cy='Cynderleena:BAABNQAECn8XAAIEAAYKvgMZCgB8AAAEAAYKvgMZCgB8AAAAAA==.Cynfully:BAAANQABCgQIBAAAAA==.Cynyia:BAABNQAECn82AAIRAAoKLhkJCwAdAgARAAoKLhkJCwAdAgAAAA==.',
Da='Daddyelessar:BAAANQAECgcICAAAAA==.Daemonfyre:BAAANQADCgEIAQAAAA==.Dafattyup:BAABNQAECn8dAAISAAgK8w3GpgCGAQASAAgK8w3GpgCGAQAAAA==.Dagon:BAAANQAECgEIAwAAAA==.Dagreenmeany:BAAANQAECgIIBgAAAA==.Dakotarain:BAAANQABCggIDQAAAA==.Darruin:BAACNQAFFH8UAAITAAQKQSVtAQAuAQATAAQKQSVtAQAuAQA1AAQKfy4AAhMACgrjJDkKAGsDABMACgrjJDkKAGsDAAAA.Dawncrow:BAAANQADCggIFwAAAA==.',
De='Deadite:BAAANQAECgEIAQAAAA==.Deathblitz:BAAANQAECgQIBwABNQAECggIEQAFAAAAAA==.Deathlydruid:BAAANQAECgEIBAAAAA==.Deathwange:BAAANQADCgcICwAAAA==.Deavaos:BAAANQAECgUIEwAAAA==.Deeanndra:BAABNQAECn8aAAITAAgKzwq4cgBMAQATAAgKzwq4cgBMAQAAAA==.Demiz:BAABNQAECn8uAAIIAAkKERYkXwDxAQAIAAkKERYkXwDxAQAAAA==.Demonicus:BAAANQAECgYIEQAAAA==.Deredris:BAAANQAECgQICgABNQAECgYIEAAFAAAAAA==.',
Di='Discodruid:BAAANQAECgQICwAAAA==.Discover:BAAANQAECgEIAQAAAA==.Dixie:BAAANQADCgcIDwAAAA==.',
Dk='Dkgrappler:BAAANQADCgcICAAAAA==.',
Do='Dollemince:BAAANQAECgEIAQAAAA==.Domittila:BAAANQAECgQIBwABNQAFFAYIEgAIAK0KAA==.Dommy:BAAANQAECgEIAQAAAA==.Donatello:BAAANQABCgYIBgAAAA==.Donham:BAACNQAFFH8WAAQUAAcKcRv5BQCkAQAUAAUKhhn5BQCkAQATAAQK0R0ICwBeAQAVAAIKHSO0GwC6AAA1AAQKfyIABBUACQqhJHwIALEBABMACApGI2AmAKMCABUABAooI3wIALEBABQAAgqeIpiBAKYAAAAA.Dorkimedes:BAAANQAECgUIDQAAAA==.Dottie:BAABNQAECn8tAAISAAoKzAvNFwCUAQASAAoKzAvNFwCUAQAAAA==.',
Dr='Draelesh:BAAANQAECgUICQAAAA==.',
Du='Dudeabides:BAAANQAECgEIAgABNQAECgYIEAAFAAAAAA==.Durenn:BAABNQAECn8rAAILAAoK6CExCQCdAwALAAoK6CExCQCdAwABNQAFFAQIFAATAEElAA==.Duskmane:BAAANQAECgEIAQAAAA==.Dux:BAAANQADCgEIAQAAAA==.',
Dw='Dwadler:BAAANQAECgUIEQAAAA==.',
Dy='Dyrkazen:BAAANQAECgUIEwAAAA==.',
Ec='Eclipses:BAAANQADCgcIEAAAAA==.',
Ed='Edris:BAAANQAECgUICAABNQAFFAYIEgAIAK0KAA==.',
El='Elesaelyre:BAAANQADCgEIAQAAAA==.Elvi:BAAANQADCgYICwABNQAECgkJJAATAHEXAA==.',
Em='Emberash:BAAANQADCgUIBgAAAA==.Embre:BAABNQAECn8sAAMWAAoK7xrrHwBXAQAWAAUK+RfrHwBXAQAPAAoKiA6UDAD7AAAAAA==.',
Er='Erébus:BAAANQAECgcIEQABNQAECgcIHQADAIgeAA==.',
Eu='Euryphaessa:BAAANQAECgEIAQABNQAECggIEQAFAAAAAA==.',
Ev='Evergreene:BAAANQADCgcICAABNQADCggIEQAFAAAAAA==.Evlpotato:BAAANQADCggIFAAAAA==.Evojak:BAAANQAECgUIDwAAAA==.',
Ew='Ewanar:BAACNQAFFH8SAAMIAAYKrQp4CgCnAQAIAAYKrQp4CgCnAQALAAEKAAAcNABBAAA1AAQKfxgAAwgACArkFz5tAMMBAAgACArkFz5tAMMBAAsAAwoYGF1bAIQAAAAA.',
Fa='Faevelia:BAAANQADCgcIGAAAAA==.Fanshen:BAAANQADCggIEwAAAA==.Fatasspos:BAAANQAECgQIBgAAAA==.Fauchi:BAAANQADCgEIAQAAAA==.Faxqueenmage:BAAANQAECgcICwAAAA==.',
Fe='Feldo:BAAANQADCgYIEQAAAA==.Feralarak:BAAANQADCgUIBQABNQAFFAcIEwACAAsgAA==.Ferndugen:BAAANQAECgIIAgAAAA==.',
Fi='Fishtank:BAAANQAECgQJBQABNQAECgoKMgARAMQVAA==.Fizehbubbleh:BAEANQADCgYIBgABNQAECgQICAAFAAAAAA==.Fizehtotems:BAEANQAECgQICAAAAA==.',
Fo='Foragarn:BAAANQAECgIIAgAAAA==.',
Fr='Frankkastle:BAAANQADCgcIEgAAAA==.Fribble:BAAANQAECgYIDQABNQAECgYIEAAFAAAAAA==.Froggierlynx:BAAANQADCggICAAAAA==.Frostalot:BAAANQAECgEIAQAAAA==.Froznfate:BAAANQAECgYIEwAAAA==.',
Fu='Fuzziebutt:BAAANQADCgYIEQAAAA==.',
Fw='Fwibble:BAAANQAECgYIEAAAAA==.',
Fy='Fyrelady:BAAANQADCggIHAAAAA==.Fyrestone:BAAANQADCgEJAQABNQADCggIHAAFAAAAAA==.',
Ga='Gabbey:BAEANQAECgcIDAABNQAECgoKMQAXAIwTAA==.Gaboldor:BAAANQADCgUIBQAAAA==.Gamman:BAAANQAECgcICQAAAA==.Garagon:BAABNQAECn8YAAIPAAUKIQscEADRAAAPAAUKIQscEADRAAAAAA==.Garlicbread:BAAANQAECgQIBwAAAA==.Gauss:BAAANQAECgQICAABNQAECgYIEAAFAAAAAA==.Gavx:BAAANQADCggIFAAAAA==.',
Ge='Gerva:BAABNQAECn8VAAITAAUKkBBFLACxAAATAAUKkBBFLACxAAAAAA==.',
Gh='Ghorfindor:BAAANQAECgQIDAAAAA==.Ghostems:BAACNQAFFH8JAAIBAAYK8w0IGAC4AQABAAYK8w0IGAC4AQA1AAQKfxoAAgEACQqsEzdPAB0BAAEACQqsEzdPAB0BAAAA.',
Gi='Gilas:BAABNQAECn8aAAMVAAcK6AqwcwAnAQAVAAcKkQqwcwAnAQATAAUKLweTkwDdAAAAAA==.',
Gl='Glaedr:BAAANQAECgYIDgABNQADCggIFgAFAAAAAA==.Glee:BAAANQADCgUIBQAAAA==.Globeasaure:BAABNQAECn8cAAIKAAYKvwc2nwCfAAAKAAYKvwc2nwCfAAAAAA==.',
Gn='Gnikole:BAAANQAECgUIDwAAAA==.',
Go='Goswin:BAAANQAECgUIEAAAAA==.',
Gr='Grappler:BAAANQADCggICAAAAA==.Gravebjorn:BAAANQADCgUICAABNQAECgMIAwAFAAAAAA==.Greenfelpowa:BAAANQAECgYIDQAAAA==.Grimsin:BAAANQADCgQIBAAAAA==.Gruuven:BAAANQAECgcJDwAAAA==.',
Gu='Gutmtmon:BAAANQADCggIBQAAAA==.',
Gw='Gwenivive:BAABNQAECn8cAAIRAAkKahbeWwBhAgARAAkKahbeWwBhAgAAAA==.',
['Gí']='Gízmo:BAABNQAECn8YAAIRAAgKzQ/yhQD/AQARAAgKzQ/yhQD/AQAAAA==.',
['Gû']='Gûnter:BAAANQADCgUJCgAAAA==.',
Ha='Hakaii:BAABNQAECn8hAAMUAAcKDQpQMADbAAAUAAcKmwVQMADbAAAVAAQKHRA+lgCyAAAAAA==.Happyness:BAAANQADCgYJBgAAAA==.Haunt:BAAANQAECgUIBQAAAA==.',
He='Hellzhunter:BAAANQADCgUIBQAAAA==.Hellzhûnter:BAAANQADCggIDQAAAA==.Hellzknîght:BAABNQAECn8aAAMUAAcKbg29WgA/AQAUAAcK7wy9WgA/AQATAAUKrgl8kADmAAAAAA==.Hellzshaman:BAAANQADCgIJAgAAAA==.Hellzwarlock:BAAANQADCgEIAQAAAA==.Hexwife:BAAANQADCgIIAgAAAA==.Hexxen:BAAANQAECgQICwAAAA==.',
Ho='Holek:BAABNQAECn9BAAIRAAoK7R9lDAAPAgARAAoK7R9lDAAPAgAAAA==.Holgo:BAACNQAFFH8JAAIYAAYKZg8FBQA3AQAYAAYKZg8FBQA3AQA1AAQKfx4AAhgACgoLGL0SAMMBABgACgoLGL0SAMMBAAAA.Holstop:BAABNQAECn8iAAIYAAkKMB4GJQBxAQAYAAkKMB4GJQBxAQABNQAFFAYIHQAPANcmAA==.Holykimoly:BAAANQAECgYIDAABNQAECgoKKAAZAIwdAA==.Honsz:BAAANQAECgEIAQAAAA==.Honzz:BAAANQAECgEIBgAAAA==.Hoodrich:BAAANQADCgYIBwABNQAECgMIBAAFAAAAAA==.',
Hu='Hugecowballs:BAAANQAECgIIAgAAAA==.Huntaholic:BAAANQAECgYIEQAAAA==.',
Hy='Hyperbull:BAAANQADCgQIBAAAAA==.',
Ic='Icia:BAABNQAECn8oAAMHAAgK1x7ZJgDPAgAHAAgK1x7ZJgDPAgAaAAEKAAA6hwAiAAAAAA==.Icicle:BAAANQAECgMIBAAAAA==.',
Is='Isaic:BAAANQADCgYIBgAAAA==.Isalia:BAAANQADCgQIBwAAAA==.Iseila:BAABNQAECn8kAAIQAAoKUhVKCgAmAgAQAAoKUhVKCgAmAgAAAA==.Isevio:BAAANQADCggIEQAAAA==.',
It='Ithorus:BAAANQAECgEIAQAAAA==.',
Ja='Jaadb:BAAANQADCgQIBAAAAA==.Jaadd:BAAANQAECgIIAgAAAA==.Jaade:BAAANQAECgIIAgAAAA==.Jaadi:BAAANQAECgEIAQAAAA==.Jaiswizzle:BAABNQAECn8kAAMVAAoK5hqMAwA2AgAVAAoK5hqMAwA2AgATAAEKMAZY6gArAAAAAA==.Jamien:BAABNQAECn8eAAMKAAcKkBMrcADlAAAKAAYKsRYrcADlAAANAAMKWAbi+wCFAAAAAA==.Jasnos:BAAANQAECgQIDQAAAA==.Jayy:BAAANQAECgMIAwAAAA==.',
Je='Jean:BAAANQAECgcIEgAAAA==.',
Ka='Kaathe:BAAANQAECgMIEgAAAA==.Kaidiis:BAABNQAECn8YAAIKAAcKxQgU4wBVAQAKAAcKxQgU4wBVAQAAAA==.Karbonn:BAAANQAECgUICgAAAA==.Katiwompus:BAAANQAECgIIAgAAAA==.Katrina:BAAANQADCgIIAgABNQAECgoKPgAXAKITAA==.Kay:BAAANQAECggICAAAAA==.',
Ke='Kegbreaker:BAABNQAECn8sAAIHAAkKHxaeSABMAgAHAAkKHxaeSABMAgAAAA==.Keleden:BAAANQADCgYIBgAAAA==.',
Kh='Khanas:BAAANQAECgUICQAAAA==.',
Ki='Kikieo:BAAANQADCgQIBAAAAA==.Kimbliddan:BAABNQAECn8oAAIZAAoKjB2FBAD8AgAZAAoKjB2FBAD8AgAAAA==.Kimbustible:BAAANQAECgcIDgABNQAECgoKKAAZAIwdAA==.',
Kn='Knockknocko:BAAANQADCgcIDAAAAA==.Knova:BAAANQAECgYICAAAAA==.',
Ko='Komodostyle:BAABNQAECn8mAAIPAAgKFwfgCAA0AQAPAAgKFwfgCAA0AQAAAA==.Koobideh:BAAANQADCggICAAAAA==.Koqsnot:BAABNQAECn8nAAIBAAkKNgYMPgBBAQABAAkKNgYMPgBBAQAAAA==.',
Kr='Krisarugala:BAABNQAECn8YAAIMAAcKMA+EUwCMAQAMAAcKMA+EUwCMAQAAAA==.',
Ku='Kujoluvsmilf:BAAANQADCgcIEgAAAA==.Kunuku:BAAANQAECgcICAAAAA==.Kurogami:BAAANQADCgQIBQAAAA==.Kurogen:BAAANQADCgcIDgAAAA==.',
Ky='Kyndrissa:BAAANQABCgEJAQAAAA==.',
['Kë']='Këy:BAABNQAECn8UAAITAAcKNxRFZgB4AQATAAcKNxRFZgB4AQAAAA==.',
['Kö']='Köloth:BAAANQADCgMJAwAAAA==.',
La='Lanasia:BAAANQADCggICwAAAA==.Lancashire:BAAANQADCgMIAwAAAA==.Larchel:BAACNQAFFH8HAAMLAAIKPwuIJgCSAAALAAIKPwuIJgCSAAAIAAIKhwI7JwBrAAA1AAQKfy0AAwsACQqgF2U+AHwCAAsACQqgF2U+AHwCAAgAAgr7BAV5AGMAAAAA.Larthanar:BAAANQADCgYIBgAAAA==.Latrice:BAACNQAFFH8TAAMQAAcK4B1RAAAyAgAQAAcKHx1RAAAyAgABAAQKuhu0JgBRAQA1AAQKfyYAAwEACgrCIzVCAAADAAEACQpHJDVCAAADABAABArfIl0eAPkAAAAA.Lazerturkey:BAABNQAECn8eAAIDAAkKiBQFFwD7AQADAAkKiBQFFwD7AQAAAA==.Laërtes:BAAANQAECgQICwAAAA==.',
Le='Leiamirage:BAAANQADCgIIAgAAAA==.Leviscus:BAAANQADCgcIFwAAAA==.',
Li='Lianne:BAAANQAECgcIBwABNQABCgEIAQAFAAAAAA==.Lightbill:BAABNQAECn8lAAMNAAkK4RkkQABkAgANAAkK4RkkQABkAgAKAAIKSQkudAFpAAAAAA==.Lightbàne:BAAANQADCggIDgAAAA==.Lilriotz:BAAANQAECgMIAwAAAA==.Lilriotzz:BAABNQAECn8uAAIIAAoKLxqjKADBAgAIAAoKLxqjKADBAgAAAA==.Lilxblitzx:BAABNQAECn8YAAINAAcKTgsNPwDuAAANAAcKTgsNPwDuAAAAAA==.Lilzdrlockz:BAAANQADCgQIBAAAAA==.Lilzriotz:BAAANQAECgQIBQAAAA==.Lilzzriotz:BAAANQAECgEIAQAAAA==.',
Lo='Locomotion:BAAANQABCggICgABNQADCgYIBgAFAAAAAA==.Lovecraft:BAAANQADCgQIBAAAAA==.',
Lu='Lucyvar:BAABNQAECn8eAAIXAAkKsQSsJgDVAAAXAAkKsQSsJgDVAAAAAA==.Luma:BAAANQAECgQIBwAAAA==.',
['Lü']='Lüma:BAAANQADCgUIBQAAAA==.',
Ma='Marhukai:BAABNQAECn8jAAMKAAkKuxaYZQBqAgAKAAkKuxaYZQBqAgAJAAQKsBYpTQC0AAAAAA==.Marlow:BAABNQAECn8YAAISAAgKPRPxGQCJAQASAAgKPRPxGQCJAQAAAA==.Marotal:BAABNQAECn8hAAIBAAgKRBH8ugAOAgABAAgKRBH8ugAOAgAAAA==.Martysparty:BAAANQAECgIIBQAAAA==.Mavaena:BAAANQADCgYICwAAAA==.Maxlife:BAAANQAECggIBgAAAA==.Maylaria:BAAANQADCgUIBQAAAA==.',
Me='Meashafurry:BAAANQAECgEIAgAAAA==.Mechaboomer:BAABNQAECn8YAAIRAAUKohREUAARAQARAAUKohREUAARAQAAAA==.Megafire:BAAANQADCgcIFQAAAA==.Megahertz:BAAANQAECgEIAgAAAA==.',
Mh='Mhael:BAAANQAECgQIDAAAAA==.',
Mi='Minogon:BAAANQADCgEIAQAAAA==.Minotaur:BAAANQADCggICAAAAA==.Minphoria:BAAANQAECgEIAgAAAA==.Minsofar:BAAANQAECgEIAwAAAA==.Mistilinn:BAABNQAECn8lAAIbAAkKiQJXSwAIAQAbAAkKiQJXSwAIAQAAAA==.Miyri:BAAANQAECgEIAgABNQAECgkJLAAcABgkAA==.',
Mo='Mongarg:BAAANQADCgQIBAAAAA==.Moopandax:BAACNQAFFH8UAAIMAAYKBR5hBQBPAgAMAAYKBR5hBQBPAgA1AAQKf6YAAgwACgrSJR0AAI4DAAwACgrSJR0AAI4DAAAA.Morpheus:BAAANQAECgMIBwAAAA==.Moxsdeaths:BAAANQAECggIBgAAAA==.Moxshunter:BAAANQAECggIBgAAAA==.',
Mu='Murk:BAAANQADCggIDAAAAA==.Mushaboom:BAAANQADCgUICQAAAA==.Muzzler:BAABNQAECn8rAAMQAAgKyxWEHgD3AAAQAAUKMBiEHgD3AAABAAgKyxX3ZQDxAAAAAA==.',
My='Myeyes:BAAANQAECgEIAgAAAA==.Mylinkah:BAAANQAECgYICAAAAA==.Mynamefizz:BAEANQAECgQICQABNQAECgQICAAFAAAAAA==.Mythlok:BAAANQADCgYIBgAAAA==.',
['Má']='Mára:BAAANQADCgYIBgAAAA==.',
['Mé']='Méasha:BAAANQAECgIIAgAAAA==.',
Ni='Nicola:BAABNQAECn8VAAMHAAkKFRjMTwA1AgAHAAkKFRjMTwA1AgAaAAEKAAB+hgAjAAAAAA==.Nightxwish:BAAANQAECgMIEAAAAA==.Nik:BAAANQAECgUICAAAAA==.',
No='Nocko:BAAANQAECgEIAQAAAA==.Nohlife:BAAANQABCgIIAgAAAA==.Noisemarine:BAAANQAECgYICgAAAA==.Norellia:BAAANQAECgcIDgAAAA==.Northspirit:BAAANQAECgUICQAAAA==.',
Nu='Nuit:BAAANQAECgIIBAAAAA==.',
Ny='Nyarlothep:BAAANQAECgMIAwAAAA==.Nymh:BAAANQAECgQIBwAAAA==.Nyx:BAAANQAECgEIAQABNQAECgcIHgAKAJATAA==.',
Oa='Oakenshièld:BAAANQADCgYIBgAAAA==.',
Od='Odinn:BAAANQAECgYICAABNQAECgkJHgACACoeAA==.Odins:BAABNQAECn8eAAMCAAkKKh7pBgAUAwACAAkKGh7pBgAUAwALAAgKixvGQwBnAgAAAA==.',
Oh='Ohforfoxsake:BAAANQADCgMIBAABNQADCggIEwAFAAAAAA==.Ohyikers:BAACNQAFFH8WAAIMAAUKoiU5BwAbAgAMAAUKoiU5BwAbAgA1AAQKf08AAwwACgrqJfYAAPUDAAwACgrqJfYAAPUDAB0AAQp8Gr06AE8AAAAA.',
Ok='Oken:BAAANQAECgMIEAAAAA==.',
Op='Opportunity:BAAANQADCgcIBwABNQAECgoKVgANAJQlAA==.',
Ot='Otso:BAABNQAECn8dAAIDAAcKiB4VEQBPAgADAAcKiB4VEQBPAgAAAA==.',
Pa='Paco:BAAANQADCgYIBgAAAA==.Paladime:BAABNQAECn8YAAIKAAcKPg3F0AB6AQAKAAcKPg3F0AB6AQAAAA==.Pallek:BAAANQAECgYICAABNQAECgoKQQARAO0fAA==.Palli:BAAANQADCggIFAAAAA==.Pangodlin:BAAANQADCgYIBQAAAA==.Pasta:BAAANQAECgQICQAAAA==.',
Pe='Perastus:BAAANQADCgYIBgAAAA==.Peroxcyde:BAAANQADCgQIBAAAAA==.Perph:BAAANQAECgEIAQAAAA==.',
Ph='Phantomarrow:BAAANQAECgEIAQAAAA==.Phantomcat:BAAANQAECgUIBwAAAA==.Phantomlock:BAABNQAECn8dAAMSAAoKQBRkWABNAgASAAoKEhRkWABNAgAEAAQKDg4lPQDNAAAAAA==.Pharasan:BAABNQAECn8XAAILAAgKDQu8ngBZAQALAAgKDQu8ngBZAQAAAA==.Phatcow:BAABNQAECn8vAAIIAAoKyBv9BACWAgAIAAoKyBv9BACWAgAAAA==.Pheral:BAEANQADCgIIAgABNQAECgoKMQAXAIwTAA==.Phude:BAABNQAECn87AAIKAAoKfRaEFgDLAQAKAAoKfRaEFgDLAQAAAA==.',
Po='Pohl:BAAANQADCgYIBgAAAA==.Polymorph:BAAANQAECgEIBAAAAA==.Poohynok:BAAANQADCgYICgAAAA==.',
Ps='Psylent:BAAANQAECgUIBQAAAA==.',
Pu='Pukefeast:BAAANQAECgEIBAAAAA==.Pupcup:BAAANQAECgQIBQAAAA==.',
Py='Pyramys:BAABNQAECn8gAAMeAAgKmh3fDQBpAQAfAAUKIhz7UAB6AQAeAAgKmh3fDQBpAQAAAA==.',
['Pè']='Pèrce:BAAANQADCgUICAAAAA==.',
Qu='Quarq:BAAANQADCggIBgAAAA==.Quepaoka:BAAANQABCgMIAwAAAA==.',
Ra='Raagnar:BAAANQAECgEIAQAAAA==.Raleth:BAAANQAECgQIBAAAAA==.Rawcky:BAAANQAECgEIAQAAAA==.Razgrizz:BAAANQADCggIFwAAAA==.',
Re='Revus:BAAANQADCgQIBAAAAA==.',
Rh='Rhaya:BAAANQABCgMIAgAAAA==.',
Ri='Rialia:BAAANQAECgQIBAABNQABCgYIDAAFAAAAAA==.Rivër:BAAANQAECgUIBwAAAA==.',
Ro='Rolls:BAAANQAECgUIBQAAAA==.Ronmaclean:BAAANQADCgUIBQABNQAECgkJIAAQAOAOAA==.Rootoo:BAAANQADCgEIAQAAAA==.Roozer:BAAANQADCggIGwAAAA==.',
Sa='Sabadahoo:BAAANQAECgEIAgABNQAECgUIHAAPABsZAA==.Sad:BAABNQAECn8iAAIBAAgKhxwkHQCbAQABAAgKhxwkHQCbAQAAAA==.Saelina:BAAANQAECgYICAABNQAECgkJLAAcABgkAA==.Saelyria:BAAANQAECgYIBwABNQAECgkJLAAcABgkAA==.Sageofdeath:BAAANQADCgIIAgAAAA==.Sagepower:BAAANQADCgIIAgAAAA==.Saintfail:BAABNQAECn8bAAINAAoKggjYVACyAAANAAoKggjYVACyAAAAAA==.Sainthymn:BAABNQAECn8VAAIHAAoKiA35owApAQAHAAoKiA35owApAQABNQAECgoKGwANAIIIAA==.Sainttide:BAABNQAECn8WAAILAAkKiQOz2QDhAAALAAkKiQOz2QDhAAABNQAECgoKGwANAIIIAA==.Salv:BAAANQAECgMICQAAAA==.Sandiera:BAABNQAECn8dAAIBAAkKcwcmUAAcAQABAAkKcwcmUAAcAQAAAA==.Savallyne:BAAANQAECgEIAwABNQAECgkJLAAcABgkAA==.',
Sc='Scoreboard:BAACNQAFFH8WAAIgAAkKTBYgAABaAQAgAAkKTBYgAABaAQA1AAQKfzUAAyAACgryJuYAAJwDACAACQoIJ+YAAJwDAB8AAwrGGycpAKoAAAAA.Scupper:BAABNQAECn8sAAIgAAkKZxpSBQCdAgAgAAkKZxpSBQCdAgAAAA==.',
Se='Sedric:BAAANQAECgEIAQAAAA==.Selline:BAAANQAECgMIBAAAAA==.Selsonblue:BAAANQADCggIEwAAAA==.Sesskaa:BAABNQAECn8cAAMIAAcKpRgFVgAQAgAIAAcKpRgFVgAQAgACAAIKgwHMIgAiAAAAAA==.',
Sh='Shaqiri:BAAANQADCgYIBgAAAA==.Sharhox:BAAANQAECgUICwAAAA==.Shathos:BAAANQADCgUIAQAAAA==.Shishkbob:BAAANQAECgEIAgAAAA==.Shätterz:BAAANQADCgUJBQABNQAECgEIAQAFAAAAAA==.Shèllz:BAAANQAECgEIAQAAAA==.',
Si='Sigewulf:BAABNQAECn8VAAIVAAkK8xqTHQAJAQAVAAkK8xqTHQAJAQAAAA==.',
Sk='Skaro:BAABNQAECn8WAAIcAAYKuhSKCABSAQAcAAYKuhSKCABSAQAAAA==.Skarofox:BAAANQADCgIIAgABNQAECgYIFgAcALoUAA==.Skarosham:BAAANQAECgQIBAABNQAECgYIFgAcALoUAA==.Sketch:BAABNQAECn8iAAIfAAkKIQwrOQDwAQAfAAkKIQwrOQDwAQAAAA==.Skout:BAAANQADCgQIBAAAAA==.',
Sl='Slambulance:BAACNQAFFH8GAAIJAAIKEhIbDACAAAAJAAIKEhIbDACAAAA1AAQKfzIAAgkACgqBIJYJAAQDAAkACgqBIJYJAAQDAAAA.Sleepinslime:BAAANQAECgEIAgAAAA==.',
Sm='Smokiebear:BAAANQAECggICwAAAA==.',
So='Sobekk:BAAANQAECggICAAAAA==.Solomun:BAABNQAECn82AAINAAkKShu0IwDcAgANAAkKShu0IwDcAgAAAA==.Songa:BAAANQADCgEIAQABNQAECgMIBwAFAAAAAA==.',
Sp='Spinky:BAAANQAECgMIAwAAAA==.Sploosh:BAAANQAECgUIBgAAAA==.',
St='Stankness:BAAANQADCgUIBQAAAA==.Steak:BAAANQADCggIHwAAAA==.Stinko:BAAANQAECgQIDAAAAA==.Stoopin:BAAANQAECgEIAQAAAA==.Stormlock:BAABNQAECn8WAAISAAcKyhDFlwCrAQASAAcKyhDFlwCrAQAAAA==.Stormswar:BAAANQAECgEIAQAAAA==.Stratichnut:BAAANQAECgUIEgAAAA==.Stwampadin:BAAANQAECgQIDQAAAA==.Stwiest:BAAANQADCgcIEgABNQAECgQIDQAFAAAAAA==.',
Su='Surloyn:BAAANQADCggICAABNQAECgoKJAAVAOYaAA==.',
Sw='Swampert:BAACNQAFFH8HAAIYAAQKLBIvIwDlAAAYAAQKLBIvIwDlAAA1AAQKfy0AAhgACQrfHSYxAPsCABgACQrfHSYxAPsCAAAA.Swamperting:BAAANQAECgMIBQABNQAFFAQIBwAYACwSAA==.Swayaos:BAABNQAECn8iAAISAAkKWBAWdgAAAgASAAkKWBAWdgAAAgABNQAECgoKLgAaAEoRAA==.Swaye:BAABNQAECn8uAAIaAAoKShGkIwAVAgAaAAoKShGkIwAVAgAAAA==.Swifte:BAAANQAECgQIBQAAAA==.Swimchick:BAAANQAECgUIDAAAAA==.Swizzle:BAABNQAECn8ZAAMhAAcKOxOOFgB6AQAhAAcKOxOOFgB6AQAiAAUKNRB+QgAEAQABNQAECgoKJAAVAOYaAA==.',
Sy='Syfa:BAAANQAECgYICAAAAA==.Syllena:BAABNQAECn8sAAMcAAkKGCS1BQBDAwAcAAkKGCS1BQBDAwAiAAQKsBCmSgDRAAABNQAECgkJLAAcABgkAA==.Syndicalism:BAAANQADCgEIAQABNQADCgYIBgAFAAAAAA==.Syraelia:BAAANQAECgEIAQABNQAECgkJLAAcABgkAA==.Sythia:BAAANQADCgEIAQABNQAFFAQICAAWAEkNAA==.',
Sz='Szeto:BAAANQADCgMIBQAAAA==.',
['Sî']='Sîrprîse:BAAANQADCggIIQAAAA==.',
Ta='Tagmoo:BAABNQAECn8sAAIYAAkK8iBdKwAOAwAYAAkK8iBdKwAOAwAAAA==.Talashea:BAAANQADCgQIBAAAAA==.Talion:BAAANQADCgEIAQABNQAECggIGwADABsSAA==.Taloon:BAAANQAECgYIEAAAAA==.Taltost:BAABNQAECn8YAAIRAAYKxw+ytwCUAQARAAYKxw+ytwCUAQAAAA==.Talzith:BAAANQADCgYJBgAAAA==.Tarv:BAABNQAECn8WAAIKAAcKYQyi8AA7AQAKAAcKYQyi8AA7AQAAAA==.Tarvält:BAAANQAECgUIBgAAAA==.',
Te='Teksuo:BAABNQAECn82AAIiAAoKGhOlBgClAQAiAAoKGhOlBgClAQAAAA==.Telamontgrim:BAAANQAECgUIAwAAAA==.Tenithon:BAABNQAECn9WAAINAAoKlCWlAQDXAwANAAoKlCWlAQDXAwAAAA==.Tenscales:BAAANQAECgYICQAAAA==.Tenshenzen:BAAANQAECgIIAgAAAA==.',
Th='Thetombo:BAAANQAECgEIBQAAAA==.Tholaren:BAABNQAECn8YAAIRAAUKnREQWwD3AAARAAUKnREQWwD3AAAAAA==.Thrissa:BAAANQADCgUICQAAAA==.Thyla:BAAANQAECgEIAQAAAA==.',
Ti='Ti:BAAANQAECgIIAwAAAA==.Tinkerspell:BAAANQAECggIEQAAAA==.Tinny:BAAANQAECgEIAQAAAA==.',
Tm='Tman:BAAANQADCgcIBwAAAA==.',
To='Touchit:BAAANQAECgMICAAAAA==.Toxin:BAAANQADCggICAAAAA==.',
Tr='Traygon:BAAANQAECgMIEAAAAA==.Trevally:BAAANQADCgQIBAAAAA==.Trikshawt:BAAANQAECgYIEAAAAA==.Trillion:BAAANQAECgQICQAAAA==.',
Ts='Tsukikame:BAAANQABCgIIAgAAAA==.',
Tu='Tunzoffun:BAAANQAECgQIBQAAAA==.',
Ty='Tyfa:BAAANQAECgYICAAAAA==.',
Ud='Udari:BAABNQAECn8YAAIKAAcK3BEXRQA7AQAKAAcK3BEXRQA7AQAAAA==.',
Un='Underbyte:BAAANQAECgIIAgAAAA==.Underdose:BAAANQADCgEIAQABNQADCgYIBgAFAAAAAA==.',
Us='Usednabused:BAAANQAECgIIAwAAAA==.',
Uz='Uzume:BAAANQADCgIIAgAAAA==.',
Va='Vaghar:BAAANQAECgEIAQAAAA==.Varithal:BAABNQAECn8uAAIPAAkKYRmkEACgAgAPAAkKYRmkEACgAgABNQABCgEIAQAFAAAAAA==.Vastectomy:BAAANQAECgUIDAAAAA==.',
Ve='Veleria:BAAANQADCgMIAQAAAA==.Venawyn:BAABNQAECn8aAAIRAAcK0wk5xwBzAQARAAcK0wk5xwBzAQAAAA==.',
Vi='Vicious:BAACNQAFFH8HAAIIAAMKPhb9GgDCAAAIAAMKPhb9GgDCAAA1AAQKfykAAggACQolHrAlAM4CAAgACQolHrAlAM4CAAAA.Vixin:BAAANQAECgYIDgAAAA==.',
Vo='Voidsaack:BAABNQAECn8jAAMEAAcKaAasPwDDAAAEAAYK3ASsPwDDAAASAAUKHQVAiQByAAAAAA==.Vortan:BAABNQAECn8wAAIjAAgKZR0lAQDiAQAjAAgKZR0lAQDiAQAAAA==.',
Vr='Vreya:BAAANQADCgUIBgABNQADCggIFwAFAAAAAA==.',
Vy='Vyndrae:BAAANQAECgIJAwAAAA==.Vynthus:BAAANQAECgUIDgAAAA==.',
Wa='Warhundin:BAEANQAECgcIBAABNQAECgoKMQAXAIwTAA==.Warknown:BAAANQADCgYIBgAAAA==.Wazzbozz:BAAANQAECgQICAAAAA==.Wazzdh:BAAANQADCgIIAgAAAA==.Wazzdot:BAAANQAECgEJAQAAAA==.Wazzle:BAABNQAECn8UAAQUAAYK1guVXgAsAQAUAAYK1guVXgAsAQAVAAEKAADpxwA5AAATAAEKywY46wAqAAAAAA==.Wazzmage:BAAANQADCgYIEAAAAA==.',
Wh='Whatmyname:BAABNQAECn8ZAAIDAAYKEwveHQCiAAADAAYKEwveHQCiAAAAAA==.Whispp:BAAANQAECgQICQAAAA==.Whodisnotfiz:BAEANQADCgQIBAABNQAECgQICAAFAAAAAA==.',
Wi='Willough:BAAANQAECgEIAQAAAA==.',
Wy='Wymstar:BAAANQAECgEIAQAAAA==.Wyvoker:BAAANQADCgMIAgABNQAECgEIAQAFAAAAAA==.',
['Wÿ']='Wÿm:BAAANQADCgQIBAABNQAECgEIAQAFAAAAAA==.',
Xu='Xuny:BAAANQAECgQIBwAAAA==.',
Ya='Yahzway:BAAANQAECgEIAgAAAA==.',
Yo='Yordi:BAAANQAECgUIDgAAAA==.Yoyopapa:BAAANQADCgcIBwAAAA==.',
Yu='Yuria:BAAANQAECgQICAAAAA==.Yuzuriha:BAABNQAECn8zAAIRAAoKHiKSAwCtAgARAAoKHiKSAwCtAgAAAA==.',
Za='Zaiden:BAAANQADCgYIBgAAAA==.Zamaze:BAAANQAECgEIAQAAAA==.',
Ze='Zeekielle:BAEBNQAECn8xAAIXAAoKjBMkKgBQAgAXAAoKjBMkKgBQAgAAAA==.',
Zi='Zipy:BAABNQAECn8YAAIHAAUKsw5JQgABAQAHAAUKsw5JQgABAQAAAA==.',
Zo='Zorathar:BAAANQADCgIIAgAAAA==.',
Zy='Zyllo:BAAANQADCggIFgAAAA==.',
['Zæ']='Zæ:BAAANQAECgUIBAAAAA==.',
['Ål']='Ålïce:BAABNQAECn8wAAIKAAkK+hgLEQDyAQAKAAkK+hgLEQDyAQAAAA==.',
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
