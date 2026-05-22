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

local lookup = {'Warrior-Fury','Unknown-Unknown','Priest-Discipline','Warlock-Demonology','Shaman-Restoration','Monk-Mistweaver','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','Mage-Frost','Warrior-Arms','Warrior-Protection','Rogue-Subtlety','DemonHunter-Devourer','Druid-Restoration','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Hunter-Marksmanship','Warlock-Destruction','DeathKnight-Unholy','Shaman-Elemental','Druid-Guardian','Druid-Balance','DeathKnight-Frost','Paladin-Holy','DemonHunter-Havoc','Monk-Windwalker','Druid-Feral','Priest-Shadow','DeathKnight-Blood','Mage-Arcane','DemonHunter-Vengeance','Priest-Holy','Hunter-Survival',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aauron:BAAALgAECgMJAwAAAA==.Aazula:BAAALgAECgUJBgAAAA==.',
Ac='Acelionheart:BAAALgADCgQJCAAAAA==.Acheron:BAAALgADCgcJCQAAAA==.',
Ai='Aix:BAAALgADCgcJBwAAAA==.',
Aj='Ajrpg:BAAALgADCgQJBAAAAA==.',
Ak='Akirys:BAABLgAECn8UAAIBAAcJYxCwMgAwAQABAAcJYxCwMgAwAQAAAA==.Akusenshi:BAAALgAECgYJDwAAAA==.',
Al='Alarr:BAAALgAECgYJBwAAAA==.Albertwesker:BAAALgAECgEJAQAAAA==.Alethrix:BAAALgAECgYJDQAAAA==.Alexi:BAAALgADCgcJCwAAAA==.Alivis:BAEALgAECgQJBAABLgAECgYJDAACAAAAAA==.Alzith:BAAALgAECgQJBQAAAA==.',
Am='Amoone:BAAALgADCgUJCQAAAA==.',
An='Anarch:BAAALgADCgEJAQABLgADCgMJBgACAAAAAA==.Androcksus:BAAALgADCgMJBwAAAA==.Angelic:BAAALgAECgEJAQABLgAFFAgJLwADADMlAA==.',
Ap='Apexalpha:BAAALgAECgMJBAAAAA==.',
Ar='Areto:BAAALgADCgYJBgAAAA==.Armster:BAAALgADCgcJDAAAAA==.Arold:BAABLgAECn8eAAIEAAgJwBKlPwCfAQAEAAgJwBKlPwCfAQAAAA==.',
As='Asylia:BAACLgAFFH8KAAIFAAQJNhGCCQA5AQAFAAQJNhGCCQA5AQAuAAQKfxcAAgUACAlLGy4hABcCAAUACAlLGy4hABcCAAAA.',
At='Atlantus:BAABLgAECn8UAAIGAAYJVw2cOAD2AAAGAAYJVw2cOAD2AAAAAA==.',
Au='Aurelliae:BAABLgAECn8WAAIHAAgJtBWNMwC8AQAHAAgJtBWNMwC8AQAAAA==.',
Av='Avesiren:BAABLgAECn8VAAIIAAYJexRTFwARAQAIAAYJexRTFwARAQAAAA==.',
Ay='Ayidá:BAAALgAECgQJCAAAAA==.',
Az='Azhág:BAAALgADCgUJBAAAAA==.',
Ba='Babalú:BAAALgAECgcJDAAAAA==.Babymamaa:BAAALgAECgIJAgAAAA==.Babymuffins:BAABLgAECn8UAAIJAAYJbiF5PADJAQAJAAYJbiF5PADJAQAAAA==.Balrocc:BAAALgADCgcJCQAAAA==.',
Be='Beecrafty:BAAALgAECgEJAQAAAA==.Belanda:BAAALgAECgIJAgAAAA==.Belgord:BAAALgAECgUJCQAAAA==.Belin:BAAALgADCgkJFgAAAA==.Belmond:BAAALgAECgQJBwAAAA==.',
Bl='Blackmill:BAAALgAECgYJDAAAAA==.Blayrog:BAABLgAECn8iAAIKAAcJsxAzfwA8AQAKAAcJsxAzfwA8AQAAAA==.Bloodydemons:BAAALgADCgEJAQAAAA==.Bluerazz:BAAALgADCgMJAwAAAA==.',
Bo='Board:BAABLgAECn8pAAMLAAkJpRcWCQAJAgALAAkJWhcWCQAJAgABAAYJ/RDSUQBiAQAAAA==.Bolf:BAAALgAECgQJCAAAAA==.Boombaaby:BAABLgAECn8WAAIHAAUJXwoljAC/AAAHAAUJXwoljAC/AAAAAA==.Bootzee:BAAALgAECgYJEgAAAA==.',
Br='Brewsli:BAAALgAECgMJAwAAAA==.Brookenoel:BAAALgAECgYJDwAAAA==.Brunhilian:BAAALgAECgUJCQAAAA==.',
Bu='Buckmaster:BAAALgADCggJDAAAAA==.Bungulator:BAAALgAECgEJAgAAAA==.',
Ca='Cadun:BAABLgAECn8UAAIBAAYJMweIRgDYAAABAAYJMweIRgDYAAAAAA==.Calada:BAAALgAECgQJBgAAAA==.Carbion:BAAALgADCgkJCQAAAA==.',
Ce='Cedarnia:BAAALgADCgMJAgAAAA==.',
Ch='Charot:BAAALgAECgEJAQABLgAFFAEJAQACAAAAAA==.Cheesdhunter:BAAALgAECgMJBQAAAA==.Chronoo:BAABLgAECn8ZAAIFAAkJIBXUGAAuAgAFAAkJIBXUGAAuAgAAAA==.',
Ci='Citchelas:BAAALgAECgYJCwAAAA==.',
Co='Corrynn:BAAALgAECgYJDgAAAA==.',
Cr='Cribbage:BAABLgAECn8nAAMMAAgJYCJ+BQB7AgAMAAgJYCJ+BQB7AgALAAEJzBqnRQBKAAAAAA==.Cryoclover:BAAALgAECgQJBAAAAA==.Crzykanaka:BAAALgADCgUJBwAAAA==.',
Cu='Cursedgurly:BAAALgAECgIJAgAAAA==.Curshuu:BAAALgAECgQJDgAAAA==.',
Cy='Cynosure:BAABLgAECn8rAAINAAkJPhlBCwAkAgANAAkJPhlBCwAkAgAAAA==.Cytronsneak:BAAALgAECgEJAQAAAA==.',
Da='Dabb:BAAALgADCggJDgAAAA==.Daccard:BAAALgADCgkJGwAAAA==.Daccfu:BAAALgAECgQJCAAAAA==.Dangereuse:BAAALgADCgEJAQAAAA==.Danlor:BAABLgAECn8YAAIEAAYJcwqAhwDtAAAEAAYJcwqAhwDtAAAAAA==.Darkheaven:BAAALgAECgcJEwAAAA==.Darkkanaka:BAAALgADCgEJAQAAAA==.Darrling:BAAALgAECgYJDgAAAA==.Davethelock:BAAALgAECgIJAgAAAA==.Dazarek:BAAALgAECgcJEAAAAA==.',
De='Deadpoolx:BAAALgAECgMJBAAAAA==.Demium:BAACLgAFFH8OAAIOAAUJjRn0IQBAAQAOAAUJjRn0IQBAAQAuAAQKfykAAg4ACAmMItcTAGMCAA4ACAmMItcTAGMCAAEuAAQKBQkKAAIAAAAA.Demonkanaka:BAAALgADCgEJAQAAAA==.Deowulf:BAAALgADCgkJCQAAAA==.Desiinnorre:BAAALgADCggJCgAAAA==.Devinetoro:BAABLgAECn8WAAIJAAYJIAaHrgDTAAAJAAYJIAaHrgDTAAAAAA==.Devnull:BAAALgAECgEJAQAAAA==.Devour:BAABLgAECn8iAAIPAAkJGRcmLAD/AQAPAAkJGRcmLAD/AQAAAA==.Deznormu:BAAALgADCgEJAQAAAA==.',
Di='Diag:BAABLgAECn8bAAQQAAYJRRjtCABUAQAQAAYJRRjtCABUAQARAAQJTRK6IwCCAAASAAMJLQYlWAB0AAAAAA==.',
Do='Doree:BAAALgADCgYJBgAAAA==.Dotitndropit:BAAALgAECgQJBAAAAA==.',
Dr='Drakenn:BAAALgAECgcJEwABLgAFFAUJDgATALkKAA==.Dreadsofdeth:BAABLgAECn8VAAIKAAYJixh1ngCZAQAKAAYJixh1ngCZAQAAAA==.Dreamstate:BAAALgADCgkJCgAAAA==.Drklhtkanaka:BAAALgADCgYJBgAAAA==.Drunkenbilly:BAAALgAECgEJAQAAAA==.',
['Dê']='Dêv:BAABLgAECn8gAAIEAAgJMg/1SgB7AQAEAAgJMg/1SgB7AQAAAA==.',
Ei='Einheri:BAABLgAECn8iAAIBAAcJqxvCGwDAAQABAAcJqxvCGwDAAQAAAA==.',
Ek='Eksos:BAAALgADCgcJBwAAAA==.',
El='Elalian:BAAALgADCggJEAAAAA==.Elracc:BAAALgAECggJDgAAAA==.Eltoronegro:BAAALgADCgEJAQAAAA==.Elure:BAAALgADCgEJAQAAAA==.',
En='Endarius:BAAALgADCgMJAwAAAA==.Endeavour:BAACLgAFFH8KAAINAAMJkw8CGgDsAAANAAMJkw8CGgDsAAAuAAQKfyoAAg0ACQkSFzoKADUCAA0ACQkSFzoKADUCAAAA.Enoira:BAAALgAECgEJAQAAAA==.Enver:BAAALgADCgYJBgAAAA==.',
Ep='Epistle:BAAALgAECgQJBAAAAA==.',
Er='Erfing:BAAALgADCgcJCAAAAA==.Erinoa:BAAALgADCgEJAQAAAA==.',
Ev='Evillizard:BAABLgAECn8VAAISAAcJJgoCNwD8AAASAAcJJgoCNwD8AAAAAA==.',
Ex='Exhumer:BAABLgAECn8YAAIJAAYJ9yVKJQAnAgAJAAYJ9yVKJQAnAgAAAA==.',
Fa='Faffard:BAAALgAECgYJEAABLgAECgkJLQAUAAgIAA==.Fame:BAAALgAFFAEJAQABLgAFFAUJFAASAFEZAA==.Fara:BAAALgADCgMJAwAAAA==.Farsighted:BAAALgAECgEJAQAAAA==.',
Fe='Fearbilly:BAAALgAECgQJBwAAAA==.Fennerick:BAAALgAECgUJDQAAAA==.Feyndra:BAAALgAECgYJBgAAAA==.',
Fi='Fizzlenips:BAAALgAECgQJBAAAAA==.',
Fl='Flap:BAACLgAFFH8UAAISAAUJURkdGAAzAQASAAUJURkdGAAzAQAuAAQKfxkAAxIACAlOGG4cAOQBABIACAlOGG4cAOQBABAAAQkAAJ5AAC8AAAAA.Fleureena:BAAALgADCgYJDQAAAA==.',
Fy='Fystie:BAAALgAECgYJEAABLgAECgkJLQAUAAgIAA==.',
Ga='Galpally:BAAALgAECgYJEgAAAA==.Ganzar:BAAALgADCgMJBAABLgAFFAMJBwAVAJQjAA==.Garin:BAAALgAECgUJBgAAAA==.',
Ge='Gennic:BAAALgADCgcJBwAAAA==.',
Gi='Gishongar:BAAALgADCgkJCQAAAA==.',
Gl='Glorak:BAABLgAECn8cAAIHAAcJlgWnfwDdAAAHAAcJlgWnfwDdAAAAAA==.',
Gr='Grashen:BAABLgAECn8YAAIFAAYJsh3KIADzAQAFAAYJsh3KIADzAQAAAA==.Gravorik:BAAALgAECgUJCgAAAA==.Greefkarga:BAAALgADCgkJCgAAAA==.Grogu:BAAALgAECgYJDgAAAA==.',
Gs='Gsm:BAABLgAECn8eAAIWAAYJRhFlNgAFAQAWAAYJRhFlNgAFAQAAAA==.',
Gu='Gulritz:BAAALgAECgEJAQAAAA==.',
Ha='Hante:BAAALgADCgcJCwAAAA==.Hartmonster:BAAALgAECgQJBAAAAA==.Hawaiianchi:BAAALgADCgQJBAAAAA==.Hawaiianvoid:BAAALgADCgYJBgAAAA==.',
He='Hellmouth:BAAALgADCgQJBAAAAA==.',
Hi='Hiawassee:BAABLgAECn8UAAMHAAcJIQVmbQAfAQAHAAYJ0gVmbQAfAQATAAEJrgEiNgAaAAAAAA==.',
Ho='Holydps:BAAALgAECgcJDgAAAA==.Holyloh:BAAALgADCgIJAgAAAA==.Hoompukka:BAAALgAECgEJAQAAAA==.',
Hy='Hypia:BAAALgADCgEJAQAAAA==.',
Ii='Iit:BAAALgADCgcJBgAAAA==.',
Il='Ilokana:BAAALgAECgEJAgAAAA==.',
In='Inuyashi:BAAALgADCgMJAwAAAA==.',
Ir='Ironfist:BAAALgAECgYJCwAAAA==.',
It='Itzbarney:BAAALgAECgYJBgAAAA==.',
Ja='Jacsace:BAAALgADCgQJBAAAAA==.Jacspally:BAAALgAECggJEQAAAA==.Jailbayt:BAAALgAECgYJCgAAAA==.Janora:BAABLgAECn8YAAIXAAgJ+x40BQBhAgAXAAgJ+x40BQBhAgAAAA==.Jarlath:BAAALgADCgEJAQAAAA==.',
Je='Jebra:BAABLgAECn8dAAIYAAYJRxEpLwAIAQAYAAYJRxEpLwAIAQAAAA==.Jellexy:BAAALgAECgYJEAAAAA==.',
Jo='Jolah:BAAALgADCgMJAwAAAA==.Jolahbae:BAACLgAFFH8KAAIGAAMJFxVXHQDNAAAGAAMJFxVXHQDNAAAuAAQKfzAAAgYACAk2HfUPAD0CAAYACAk2HfUPAD0CAAAA.Jonnyfive:BAAALgAECgMJAwAAAA==.',
Ka='Kaehlen:BAAALgADCgkJCQAAAA==.Kaigon:BAAALgADCgEJAQAAAA==.Kailis:BAABLgAECn8jAAIHAAkJ6heVGABGAgAHAAkJ6heVGABGAgAAAA==.Kaisa:BAAALgADCgcJBwAAAA==.Kanne:BAAALgADCgMJAwAAAA==.Karst:BAAALgAECgYJEAAAAA==.Katsudin:BAAALgAECgUJBQAAAA==.Kayzon:BAACLgAFFH8nAAMHAAgJ8B6zAABsAgAHAAcJnyOzAABsAgATAAYJEw3CCgBuAQAuAAQKf0AAAwcACQkfJjgCAEoDABMACQkYIo8CAIkDAAcACQkfJjgCAEoDAAAA.Kayzwei:BAAALgAECgYJEwAAAA==.',
Ke='Kegtap:BAAALgAECgQJBAAAAA==.Keheo:BAAALgAECgMJAwAAAA==.',
Ki='Kij:BAAALgAECgEJAQAAAA==.Kill:BAAALgAECgYJCQAAAA==.Killaks:BAAALgAECgYJBgAAAA==.Killdo:BAAALgAECgEJAQAAAA==.Kirilla:BAAALgADCgEJAQAAAA==.',
Kl='Klavine:BAABLgAECn80AAIZAAkJMRo8AgCnAgAZAAkJMRo8AgCnAgAAAA==.Klavinester:BAAALgAECgcJBwAAAA==.',
Ko='Korben:BAABLgAECn8fAAIaAAkJbRfBJgD0AQAaAAkJbRfBJgD0AQAAAA==.Korenna:BAAALgADCgUJCgAAAA==.',
Kr='Kronn:BAAALgAECgIJAgAAAA==.Kruger:BAABLgAECn8aAAIEAAcJAAYgggD3AAAEAAcJAAYgggD3AAAAAA==.Kryptonicboy:BAAALgAECgMJBAAAAA==.',
Kt='Ktanna:BAAALgAECgYJEAAAAA==.',
Ku='Kublakhan:BAAALgAECggJCwAAAA==.',
Ky='Kyfu:BAAALgADCgMJAwABLgAFFAUJFgAIAFEgAA==.Kynleria:BAAALgADCgEJAQAAAA==.',
La='Lakhi:BAABLgAECn8gAAIFAAkJixyBGgAhAgAFAAkJixyBGgAhAgAAAA==.Lapras:BAEALgAFFAkJAwAAAA==.Lateralus:BAABLgAECn8WAAIJAAgJ6gpkZwBVAQAJAAgJ6gpkZwBVAQAAAA==.Laureli:BAAALgAECgYJCgAAAA==.',
Le='Leeta:BAABLgAECn8UAAIXAAYJ1xkQEQBmAQAXAAYJ1xkQEQBmAQAAAA==.Legendx:BAAALgADCgUJBwAAAA==.',
Li='Lightningg:BAABLgAECn8UAAIQAAgJbgzzBwBvAQAQAAgJbgzzBwBvAQAAAA==.Lightsaved:BAAALgADCgIJAgAAAA==.Lightsworn:BAAALgAECgIJAgAAAA==.Linara:BAAALgADCgIJAgAAAA==.',
Lo='Lockbite:BAAALgADCgEJAQAAAA==.Lokralaila:BAAALgADCgQJBAAAAA==.Lollypopp:BAAALgAECgcJAQAAAA==.Lomme:BAAALgADCgcJBwAAAA==.Loraemar:BAAALgAECgIJAgAAAA==.Losoz:BAAALgAECgEJAQAAAA==.',
Lu='Lusilsandrus:BAAALgAECgUJDQAAAA==.Luxanna:BAAALgAECgIJAQAAAA==.',
Ma='Maegwin:BAAALgAECggJCQAAAA==.Mahoutsukai:BAAALgAECgcJEQAAAA==.Malefiscent:BAAALgADCgIJAgAAAA==.Matti:BAABLgAECn8UAAIWAAYJzgc8RwC+AAAWAAYJzgc8RwC+AAAAAA==.',
Me='Mechaknight:BAAALgAECgUJCAAAAA==.Meddler:BAAALgADCgQJBQAAAA==.',
Mi='Mildrik:BAABLgAECn8UAAIBAAgJgwdxMgAyAQABAAgJgwdxMgAyAQAAAA==.Miracledh:BAABLgAECn8WAAIbAAYJKia3CgAdAgAbAAYJKia3CgAdAgAAAA==.Mirkdrak:BAAALgAECgYJEQAAAA==.Misheard:BAABLgAECn8uAAIOAAkJeR9OEACAAgAOAAkJeR9OEACAAgAAAA==.Misjudged:BAABLgAECn8UAAQSAAcJqhAcLQAuAQASAAcJqhAcLQAuAQAQAAQJhw0dKQDWAAARAAIJghjiQgBWAAAAAA==.Missus:BAAALgAECgcJDAAAAA==.Mit:BAAALgADCgkJGAAAAA==.Miyu:BAAALgAECgEJAgAAAA==.Mizzen:BAABLgAECn8fAAIcAAcJcBovHAB8AQAcAAcJcBovHAB8AQABLgAECgkJKQALAKUXAA==.',
Mo='Mohtavius:BAABLgAECn8bAAIMAAYJURQ9GwANAQAMAAYJURQ9GwANAQAAAA==.Mohz:BAAALgADCgcJCwAAAA==.Mommydearest:BAABLgAECn8tAAIUAAkJCAjvDAAiAQAUAAkJCAjvDAAiAQAAAA==.Moonbaboon:BAAALgAECgkJDwAAAA==.Moonkissed:BAAALgAECgEJAgAAAA==.Moonrizer:BAAALgAECgIJAgAAAA==.Morttimuss:BAAALgAECgQJBQAAAA==.Motz:BAAALgADCgUJBgAAAA==.',
Ms='Msboba:BAAALgADCgYJBgAAAA==.',
Mu='Munkìe:BAAALgAECgIJAwABLgAECgYJHgAWAEYRAA==.Muura:BAABLgAECn8eAAIVAAgJ2QtFqwDMAAAVAAgJ2QtFqwDMAAAAAA==.',
My='Myextralife:BAAALgADCgYJBgAAAA==.Myrik:BAAALgAECgQJDQAAAA==.',
Na='Naslunda:BAAALgADCgIJAgAAAA==.Nathyrra:BAABLgAECn8fAAIFAAgJyxfiGwAVAgAFAAgJyxfiGwAVAgAAAA==.Nattal:BAAALgADCgUJBQAAAA==.',
Ne='Nebekenazar:BAAALgAECgYJCgAAAA==.Negate:BAAALgAFFAEJAQABLgAFFAcJHQARAGodAA==.',
Ni='Nitrö:BAAALgAECgEJAQABLgAECgQJCAACAAAAAA==.',
No='Noreset:BAAALgADCgYJBgAAAA==.Noriea:BAAALgADCgEJAQAAAA==.',
Nu='Nufonhudis:BAAALgAECgQJCAAAAA==.',
Om='Omnidacc:BAAALgAECgIJAgAAAA==.',
On='Onigirius:BAAALgAECgYJBgAAAA==.',
Op='Optional:BAAALgAECgIJAwAAAA==.',
Ot='Otwin:BAAALgAECgQJBwAAAA==.',
Pa='Pahuum:BAAALgAECgIJAgAAAA==.Paimon:BAAALgAECgUJCQABLgAFFAUJFAASAFEZAA==.Paintrainn:BAAALgAECgcJEAAAAA==.Palewhiteman:BAABLgAECn8hAAIaAAgJ5hnPEQA6AgAaAAgJ5hnPEQA6AgAAAA==.Palleigh:BAAALgAECgcJEQAAAA==.Pallyd:BAAALgADCgEJAQAAAA==.Patchës:BAAALgAECgQJCAAAAA==.',
Pe='Pepperjack:BAABLgAECn8UAAIPAAYJSxeWMwCGAQAPAAYJSxeWMwCGAQAAAA==.Persephonae:BAAALgADCgQJBAAAAA==.Persimmon:BAABLgAECn8YAAIHAAgJmBhiLADaAQAHAAgJmBhiLADaAQAAAA==.',
Pi='Pikklerikk:BAAALgAECgYJDAAAAA==.',
Po='Poondor:BAAALgAECggJEgAAAA==.Poplocndrop:BAAALgAECgQJBAAAAA==.',
Pr='Predaturd:BAAALgAECggJBAAAAA==.',
Pu='Purgatorri:BAAALgAECgQJBwAAAA==.',
Qi='Qindere:BAAALgAECgcJEwAAAA==.',
Ra='Raalaan:BAAALgADCgEJAQAAAA==.Raeinthe:BAABLgAECn85AAIHAAkJgBWfHwAaAgAHAAkJgBWfHwAaAgAAAA==.Ramantu:BAAALgADCgcJBwAAAA==.Rancor:BAAALgAECgMJBAABLgAFFAMJBwAVAJQjAA==.',
Re='Reihino:BAAALgADCgcJBwAAAA==.Resbak:BAAALgAECggJDwAAAA==.Resiaus:BAABLgAECn88AAIRAAkJyRz9AgDpAgARAAkJyRz9AgDpAgAAAA==.',
Ri='Ripptyde:BAAALgADCgQJBAAAAA==.Rivalina:BAAALgAECgYJCgAAAA==.',
Ro='Robilargreen:BAAALgADCgUJBQAAAA==.Rocketabu:BAAALgAECgMJAwAAAA==.Roctheist:BAAALgAECgYJEwAAAA==.Rocthoeb:BAABLgAECn80AAIMAAkJxRH/EQDoAQAMAAkJxRH/EQDoAQAAAA==.Rojito:BAAALgADCgkJGAAAAA==.',
Ry='Ry:BAABLgAECn8lAAMdAAgJjCE6AwCbAgAdAAgJjCE6AwCbAgAPAAEJ8AQWywAaAAAAAA==.',
Sa='Saeris:BAAALgAECgMJAwAAAA==.Saintfrosty:BAEALgADCgEJAQABLgAECggJFAADAJkTAA==.Saintkhal:BAEALgAECgQJCAABLgAECggJFAADAJkTAA==.Saintmedicus:BAEBLgAECn8UAAMDAAgJmRNFJgA+AQADAAUJZBdFJgA+AQAeAAMJ1Q0xSACOAAAAAA==.Saintshammy:BAABLgAFFH8FAAIFAAMJWxVAKADoAAAFAAMJWxVAKADoAAAAAA==.Saintshunter:BAAALgAECgEJAQAAAA==.Sanctor:BAABLgAECn8dAAIaAAcJeyJ0EgB/AgAaAAcJeyJ0EgB/AgAAAA==.Sandusky:BAAALgADCgQJBAAAAA==.Saraya:BAAALgAECgYJEQAAAA==.',
Se='Sephafael:BAAALgAECgIJAgAAAA==.Setsena:BAABLgAECn8YAAIDAAgJGxw7CgB6AgADAAgJGxw7CgB6AgAAAA==.',
Sh='Shamwow:BAAALgAECgQJBAAAAA==.Shangi:BAAALgADCgMJAwAAAA==.Shinstabber:BAABLgAECn8YAAIfAAgJWQh+IAD6AAAfAAgJWQh+IAD6AAAAAA==.Shivantis:BAAALgADCgUJBQAAAA==.Shlarya:BAAALgAECgEJAQABLgAECggJDwACAAAAAA==.Shruggie:BAABLgAECn8aAAMbAAcJYA85GwA7AQAbAAcJYA85GwA7AQAOAAIJJwRP2gArAAAAAA==.',
Si='Silven:BAAALgAECgYJCgAAAA==.Singingsword:BAAALgAECgEJAQAAAA==.Sinthras:BAAALgADCgIJAgAAAA==.Siphond:BAAALgAECgQJBAAAAA==.Siphondark:BAABLgAECn8YAAIGAAgJShs+DgBUAgAGAAgJShs+DgBUAgAAAA==.Sisqi:BAAALgADCgQJBAAAAA==.',
Sl='Slapnutz:BAABLgAECn8bAAIHAAcJ3xVxLwD0AQAHAAcJ3xVxLwD0AQAAAA==.',
Sm='Smidgen:BAAALgADCggJDgAAAA==.Smoki:BAAALgAECgUJBQAAAA==.',
So='Solvaii:BAABLgAECn8gAAITAAkJmQezDQA5AQATAAkJmQezDQA5AQAAAA==.',
St='Starfail:BAAALgAECgYJDgABLgAFFAQJCgAFADYRAA==.Starlie:BAAALgAECgUJBQAAAA==.Stratacaster:BAAALgAECgYJDAAAAA==.Strawberry:BAAALgAECgUJCwAAAA==.Stuckinwell:BAACLgAFFH8FAAMEAAIJkBjuNQCnAAAEAAIJGBDuNQCnAAAUAAEJlBY2FgBSAAAuAAQKfxsAAwQACQn6GsEzAD0CAAQACAnpFsEzAD0CABQABQkNHEAYAIgBAAAA.',
Su='Sunbound:BAABLgAFFH8LAAIPAAIJhh6QFQC3AAAPAAIJhh6QFQC3AAABLgAFFAcJHQARAGodAA==.',
Sx='Sxths:BAAALgAECgEJAQAAAA==.',
Sy='Syela:BAAALgAECgQJDAAAAA==.Synsyn:BAAALgAECgUJDgAAAA==.',
Ta='Tach:BAAALgADCgYJBgAAAA==.Tanel:BAAALgAECgYJCAAAAA==.Targonne:BAAALgADCgEJAQAAAA==.Taterhots:BAAALgADCgcJBwAAAA==.Tatsü:BAAALgAECgIJAQAAAA==.Taílorswift:BAABLgAECn8dAAIKAAkJaw3qZgBvAQAKAAkJaw3qZgBvAQAAAA==.',
Te='Teanfists:BAAALgAECgEJBQAAAA==.Temna:BAABLgAECn8eAAIJAAYJBB9JRwCnAQAJAAYJBB9JRwCnAQAAAA==.Tenari:BAAALgAECggJDwAAAA==.',
Th='Theel:BAAALgAECgQJCgAAAA==.Thespaniard:BAABLgAECn8cAAIeAAcJPhkeGwCYAQAeAAcJPhkeGwCYAQAAAA==.Thlunk:BAAALgADCgkJCQAAAA==.',
Ti='Tidebreaker:BAAALgAECgYJDwAAAA==.Tidepods:BAAALgAECgYJCgAAAA==.Tinbasher:BAAALgAECgUJBwAAAA==.',
Tj='Tjay:BAAALgADCgEJAQAAAA==.',
To='Totemistic:BAAALgADCggJCgAAAA==.',
Tr='Treebilly:BAAALgAECggJDwAAAA==.Tricky:BAAALgAECgEJAQAAAA==.Triviousox:BAAALgAECgYJEAAAAA==.',
Tu='Tungo:BAAALgADCgEJAQAAAA==.',
Tw='Twilightjade:BAAALgADCggJDwABLgAECgYJBwACAAAAAA==.Twotvmage:BAABLgAECn8sAAMKAAgJHB2IJwA7AgAKAAgJHB2IJwA7AgAgAAEJIA2EEAAxAAAAAA==.',
Ug='Uglyboyryan:BAAALgAECgQJBAAAAA==.',
Un='Unglued:BAAALgAECgEJAQAAAA==.Unholygrimg:BAAALgADCgUJBQAAAA==.Unholywar:BAAALgAECgYJCQABLgAECggJLQAEAFIbAA==.',
Up='Uplift:BAAALgAFFAMJBAABLgAFFAcJEwAKAPYZAA==.',
Ur='Ursolana:BAAALgADCgUJBQAAAA==.',
Va='Valkky:BAABLgAECn8cAAMhAAYJ7w1lEgDUAAAhAAYJBAxlEgDUAAAOAAQJOA0VowDOAAAAAA==.Valky:BAAALgADCgQJBAABLgAECgYJHAAhAO8NAA==.Valleya:BAAALgAECgIJAgAAAA==.Vallysong:BAABLgAECn8ZAAMDAAcJxBCoLgAFAQADAAUJRQ6oLgAFAQAiAAcJzwzmMQD5AAAAAA==.Valnetrois:BAAALgADCgEJAQAAAA==.Vaswislor:BAAALgAECgEJAgAAAA==.',
Ve='Velayna:BAAALgAECgYJCgAAAA==.Velenn:BAAALgAECgEJAQABLgAECgcJGQADAMQQAA==.Vellani:BAAALgAECgEJAQAAAA==.Venatar:BAABLgAECn8eAAIHAAYJLRpJTwBaAQAHAAYJLRpJTwBaAQAAAA==.Vessna:BAAALgAECgQJDAABLgAECgYJEQACAAAAAA==.',
Vi='Vicarious:BAAALgAECgYJEwAAAA==.Visea:BAAALgADCgEJAQAAAA==.Vivîán:BAAALgAECgYJDAAAAA==.',
Vm='Vmro:BAAALgADCgYJEQAAAA==.',
Vo='Voras:BAAALgAECgUJEAAAAA==.Vorttex:BAAALgAECgEJAQAAAA==.',
Wa='Waitandbleed:BAAALgADCgcJBwAAAA==.Wanglock:BAAALgAECgYJDAABLgAFFAgJHAASAGYcAA==.Wardstar:BAAALgADCgIJAgAAAA==.Wasure:BAABLgAECn8UAAIhAAYJXBorCgBsAQAhAAYJXBorCgBsAQAAAA==.',
Wh='Whiskeyrick:BAAALgADCgMJAwAAAA==.',
Wi='Wildkanaka:BAAALgADCgEJAQAAAA==.Winters:BAAALgADCggJCAAAAA==.',
Wo='Worthy:BAAALgADCgYJBgAAAA==.',
Xa='Xalatath:BAABLgAECn8YAAIeAAgJ4RsHEQB4AgAeAAgJ4RsHEQB4AgAAAA==.',
Xt='Xtra:BAAALgADCgEJAQAAAA==.',
Xy='Xylar:BAABLgAFFH8FAAIjAAMJfAcPFgDcAAAjAAMJfAcPFgDcAAAAAA==.',
Ya='Yahiko:BAAALgAECgMJAwAAAA==.',
Yu='Yuzuriha:BAAALgAECgQJCQAAAA==.',
Za='Zarazard:BAAALgAECgQJBAAAAA==.',
Ze='Zeynah:BAAALgADCgYJBgAAAA==.',
Zo='Zophier:BAAALgADCgMJAwAAAA==.',
Zu='Zube:BAAALgAECgUJBwAAAA==.',
['Âu']='Âuranna:BAAALgAECgYJCgAAAA==.',
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
