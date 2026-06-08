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

local lookup = {'Druid-Restoration','Warrior-Arms','Warrior-Fury','DemonHunter-Devourer','Priest-Holy','Mage-Frost','Mage-Fire','Priest-Discipline','Shaman-Elemental','Warlock-Demonology','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Survival','Unknown-Unknown','Warrior-Protection','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Monk-Mistweaver','Druid-Balance','Warlock-Affliction','Warlock-Destruction','DeathKnight-Blood','DemonHunter-Havoc','Rogue-Assassination','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','Priest-Shadow','DemonHunter-Vengeance','Monk-Brewmaster','Shaman-Restoration','Rogue-Subtlety','Shaman-Enhancement','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','Rogue-Outlaw',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=46,date='2026-06-07',data={Ab='Ababear:BAABLgAECn8vAAIBAAgJ4SGbDQDOAgABAAgJ4SGbDQDOAgAAAA==.Abardi:BAAALgADCgUJBgAAAA==.',
Ac='Aces:BAAALgAECgIJAgAAAA==.',
Ad='Adeki:BAAALgADCgEJAQAAAA==.',
Ae='Aedaria:BAAALgADCgMJAwAAAA==.Aegis:BAAALgAECgEJAgAAAA==.Aeira:BAAALgADCgYJCQAAAA==.Aelora:BAAALgADCgMJAwAAAA==.Aerenna:BAAALgADCgUJBQAAAA==.Aestirå:BAAALgADCgMJAwAAAA==.Aethia:BAAALgAECgYJBgAAAA==.',
Ag='Agakk:BAACLgAFFH8bAAICAAUJWB3AEwArAQACAAUJWB3AEwArAQAuAAQKfy8AAgIACQmqI1ICAAQDAAIACQmqI1ICAAQDAAAA.Agilities:BAAALgAECgQJBAAAAA==.',
Ah='Ahnna:BAAALgADCgkJEQAAAA==.',
Al='Alarrius:BAABLgAECn8sAAMDAAkJCh9RCQDGAgADAAkJCh9RCQDGAgACAAYJGRA/MAD+AAAAAA==.Albedö:BAAALgAFFAIJAgAAAA==.Aleanath:BAAALgAECggJCgABLgAECggJGgAEAHUVAA==.Alescia:BAEALgAECgYJBgABLgAECgkJLgAFAIsYAA==.Alestormia:BAAALgAFFAIJAgAAAA==.Allimental:BAAALgADCgEJAQAAAA==.Allionys:BAABLgAECn8jAAMGAAgJ/iQHFwDJAgAGAAgJ/iQHFwDJAgAHAAEJyhmvEABFAAAAAA==.Alorelia:BAAALgADCgUJBQAAAA==.Aloris:BAABLgAECn8ZAAMIAAkJWCBCEwA8AgAIAAkJXB9CEwA8AgAFAAUJNwpNSwALAQAAAA==.Alyêska:BAAALgAECgYJDQAAAA==.',
Am='Amanises:BAAALgAECgcJEwAAAA==.Amilara:BAABLgAECn8XAAIJAAgJ1A3IOABHAQAJAAgJ1A3IOABHAQAAAA==.',
An='Ananaya:BAAALgAECgYJDgABLgAECggJMAAKAK8UAA==.Anania:BAAALgAECgUJBQAAAA==.Andinestiri:BAABLgAECn8cAAILAAkJqhQ8LgAaAgALAAkJqhQ8LgAaAgAAAA==.Andolastrasz:BAAALgAECgMJAwAAAA==.Andy:BAAALgAECgEJAgAAAA==.Aneethea:BAAALgADCgYJCQAAAA==.Anniklynn:BAAALgAECgEJAgAAAA==.Antaric:BAABLgAECn8UAAIMAAYJERKqlwAyAQAMAAYJERKqlwAyAQAAAA==.Anyalem:BAAALgAECgEJAQAAAA==.',
Ao='Ao:BAAALgAECgYJBgAAAA==.',
Ap='Apotic:BAABLgAECn8pAAINAAkJXwrADgB7AQANAAkJXwrADgB7AQAAAA==.Apuntar:BAAALgAECgcJBwAAAA==.',
Aq='Aquamaree:BAAALgAECgYJEAAAAA==.Aquamyth:BAAALgADCgMJAwAAAA==.Aquilla:BAACLgAFFH8NAAMOAAYJaAbvFwABAQAOAAQJ/gXvFwABAQALAAQJRQeiaACzAAAuAAQKfyAAAw4ACAkWGTUMAAwCAA4ACAmFFzUMAAwCAAsABgmBG8phAEIBAAAA.',
Ar='Archenea:BAAALgAECgUJBQAAAA==.Archenore:BAABLgAECn8XAAIDAAcJagdNVQBWAQADAAcJagdNVQBWAQAAAA==.Ariisa:BAAALgAECgcJDwAAAA==.Arkify:BAAALgADCgYJBgAAAA==.Arkisnay:BAAALgADCgMJAwABLgAECgEJAQAPAAAAAA==.Armadyl:BAAALgAECgEJAQABLgAECgQJBwAPAAAAAA==.Around:BAAALgAECgMJAwAAAA==.Arrancar:BAAALgAECgYJDQAAAA==.Arrianda:BAAALgADCgQJBAAAAA==.Artiface:BAAALgAECgYJDAAAAA==.',
As='Ashw:BAABLgAECn8XAAIQAAcJURTyIQAVAQAQAAcJURTyIQAVAQAAAA==.Askip:BAAALgAECgYJEwAAAA==.Aslann:BAAALgAECgcJCQAAAA==.Asukka:BAACLgAFFH8GAAIRAAQJgBIxPgAiAQARAAQJgBIxPgAiAQAuAAQKfyMAAxEACQkpI68NAO8CABEACAmaJK8NAO8CABIABgnoFsUYAEoBAAAA.Asëya:BAAALgAECgMJBQAAAA==.',
At='Atomique:BAACLgAFFH8cAAITAAUJrhRfFAA4AQATAAUJrhRfFAA4AQAuAAQKf0QAAhMACAkXH9YGANMCABMACAkXH9YGANMCAAEuAAUUBgkiABQAkBMA.Attenborough:BAAALgAECgUJBgABLgAECgYJDwAPAAAAAA==.Atum:BAAALgAECgEJAQAAAA==.',
Au='Auggie:BAAALgADCgEJAQAAAA==.',
Av='Avalíne:BAAALgADCgUJBQAAAA==.Avesa:BAAALgAECgYJEwAAAA==.Avoidant:BAABLgAECn8VAAMBAAgJwBTVPACYAQABAAgJwBTVPACYAQAVAAEJogrrjAArAAAAAA==.',
Ay='Aydir:BAAALgADCgUJBwAAAA==.Aylithe:BAAALgAECgQJBQAAAA==.',
Az='Azanadra:BAAALgAECgQJBwAAAA==.Azazell:BAAALgAECgYJBgAAAA==.Azenea:BAABLgAECn8iAAQWAAkJlQavDQBZAQAWAAgJRwWvDQBZAQAXAAIJsQkMMwBMAAAKAAIJhwG0IAEwAAAAAA==.',
Ba='Babomage:BAEALgAFFAgJDQAAAQ==.Baculum:BAABLgAECn8dAAIYAAkJjxqaEAD2AQAYAAkJjxqaEAD2AQAAAA==.Bacõn:BAAALgAECgQJBAAAAA==.Badmoonrisin:BAAALgAECgMJAwAAAA==.Bainne:BAAALgAECgQJCAAAAA==.Ballzach:BAABLgAECn8cAAIIAAYJqh4sLwBYAQAIAAYJqh4sLwBYAQABLgAFFAgJMQAYAMYjAA==.Bartindor:BAAALgAECgEJAQAAAA==.Barul:BAAALgADCgUJBQAAAA==.Bazookabob:BAAALgAECgYJEgABLgAECgcJCwAPAAAAAA==.',
Be='Beangles:BAAALgAECgEJAQAAAA==.Bearlylegal:BAAALgAECgYJBgABLgAECgkJCAAPAAAAAA==.Becky:BAAALgAECgUJDgABLgAECgkJKgAEAE0WAA==.Beekyy:BAABLgAECn8qAAMEAAkJTRYMRwCnAQAEAAkJiBUMRwCnAQAZAAgJ2g+GHgB3AQAAAA==.Belenova:BAAALgAECgUJBgAAAA==.Bellapearl:BAABLgAECn8UAAIKAAcJiQpAhgAoAQAKAAcJiQpAhgAoAQAAAA==.Berkyn:BAAALgADCgMJAwAAAA==.Beverly:BAAALgAECgcJCAAAAA==.Beymax:BAAALgADCgQJBAAAAA==.',
Bi='Bigbutter:BAAALgAECgQJBAAAAA==.Bittydrood:BAAALgAECgIJAgAAAA==.Bittylexis:BAAALgAECgYJEAAAAA==.',
Bl='Blakheart:BAACLgAFFH8HAAIaAAMJwBfSBgD1AAAaAAMJwBfSBgD1AAAuAAQKfzgAAhoACQkIGNcDAFwCABoACQkIGNcDAFwCAAAA.Bleuopal:BAAALgADCgcJDAAAAA==.Blueaxle:BAABLgAECn8wAAMbAAkJsxrXDgCgAgAbAAkJsxrXDgCgAgARAAIJpgHNMQFAAAAAAA==.Blur:BAAALgAECgcJEwAAAA==.Bluzzy:BAAALgAECgQJBwABLgAFFAMJCgAGAMIhAA==.Blèu:BAABLgAECn8zAAIUAAkJfBgaEQCJAgAUAAkJfBgaEQCJAgAAAA==.',
Bo='Boomdoom:BAAALgAECgQJBAAAAA==.Bootycat:BAAALgADCgcJBwABLgADCgkJCgAPAAAAAA==.Bouffenièce:BAAALgAECgQJBwAAAA==.Boufsy:BAAALgADCgkJEQAAAA==.',
Br='Brakii:BAAALgAECgIJAgAAAA==.Breathe:BAACLgAFFH8JAAIBAAMJTBzDLAD9AAABAAMJTBzDLAD9AAAuAAQKfxoAAwEABwkPHs0nAAoCAAEABwkPHs0nAAoCABUAAQlAD1WGADMAAAAA.Brewballs:BAABLgAECn82AAIUAAkJ/w0JNACRAQAUAAkJ/w0JNACRAQAAAA==.Brewjitzu:BAAALgAFFAIJBAAAAA==.Bruticusmax:BAAALgADCgUJBQAAAA==.Brynarra:BAAALgADCgUJBQAAAA==.',
Bu='Bubbletea:BAABLgAECn8aAAIKAAYJwgtbnQD/AAAKAAYJwgtbnQD/AAAAAA==.Bunnicula:BAABLgAECn8wAAMWAAkJcxoEBQAyAgAWAAkJcxoEBQAyAgAKAAUJ5wl/qgDpAAAAAA==.Bunny:BAAALgADCgYJBgABLgAECgkJMAAWAHMaAA==.',
Bw='Bwanga:BAAALgAECgYJDwAAAA==.',
['Bö']='Böömer:BAAALgAECgYJDwAAAA==.',
Ca='Caelphia:BAAALgAECgcJCwAAAA==.Calistini:BAAALgAECgkJDAAAAA==.Calmac:BAACLgAFFH8GAAIUAAMJIQcAPwCLAAAUAAMJIQcAPwCLAAAuAAQKfxYAAhQABgnFG+AoAM4BABQABgnFG+AoAM4BAAAA.Cameron:BAAALgAECgYJDAAAAA==.Capetonrex:BAAALgAECgEJAQAAAA==.Cappicola:BAAALgAECgEJAQAAAA==.Carinaxx:BAAALgAECgEJAQAAAA==.Cavall:BAAALgAECgMJAwAAAA==.Caythus:BAACLgAFFH8IAAMXAAMJiB78EABeAAAKAAIJ8xuHkACUAAAXAAEJsCP8EABeAAAuAAQKfxYAAxcABwnhJLsLAAYCABcABQkPJLsLAAYCAAoABQnmIhNRANUBAAAA.',
Ce='Celeana:BAABLgAECn8ZAAMXAAgJHx4xAwBfAgAXAAgJHx4xAwBfAgAKAAIJZQlVAgFXAAAAAA==.Celeleron:BAAALgADCgkJEAAAAA==.Celencia:BAAALgAECgcJDgAAAA==.',
Ch='Chadmcguffin:BAABLgAECn8cAAISAAkJpCNqCABSAgASAAkJpCNqCABSAgABLgAFFAMJCAACAKEaAA==.Chaelin:BAAALgAECgcJBgAAAA==.Chakabad:BAAALgAECgkJEwAAAA==.Chalgar:BAAALgAECgUJBwAAAA==.Chaosblossom:BAAALgADCgYJBwAAAA==.Cheezeballs:BAAALgADCgEJAQABLgAFFAMJBQAcAPsTAA==.Chenahala:BAABLgAECn8WAAILAAYJZgm4mwD9AAALAAYJZgm4mwD9AAAAAA==.Chibeard:BAAALgAECgkJCAAAAA==.Chåni:BAAALgAECgYJEwAAAA==.',
Ci='Ciege:BAABLgAECn8oAAMcAAkJ1BNlIwC4AQAcAAkJjhFlIwC4AQAdAAYJABKeDgAYAQAAAA==.Cinrah:BAABLgAFFH8NAAIEAAcJ/A/hHQCpAQAEAAcJ/A/hHQCpAQAAAA==.',
Cl='Clisa:BAAALgADCgIJAgAAAA==.Cloudwalker:BAABLgAFFH8IAAIeAAUJEgfnHwDTAAAeAAUJEgfnHwDTAAAAAA==.',
Co='Coffeelatte:BAAALgAECgEJAQAAAA==.Complainz:BAAALgAECgEJAQAAAA==.Conanascus:BAAALgAECgQJBwABLgAECgkJQwAaAI0WAA==.Concinnat:BAAALgADCgUJBQAAAA==.Confessorr:BAAALgADCgYJBgAAAA==.Cosantóir:BAAALgAECgUJBgAAAA==.',
Cr='Crispysock:BAAALgAECgkJEwAAAA==.Croda:BAAALgAECggJEQAAAA==.Crowe:BAAALgAECgYJCAAAAA==.Cröno:BAAALgAECgYJDAAAAA==.',
Cu='Cursez:BAABLgAECn8XAAIKAAYJYxPTiwAeAQAKAAYJYxPTiwAeAQABLgAFFAgJKgAJAC4cAA==.',
Cy='Cynderr:BAAALgAECgcJEAAAAA==.',
['Cè']='Cèrc:BAAALgAECgIJAwAAAA==.',
Da='Daemian:BAACLgAFFH8IAAICAAMJoRpMGgADAQACAAMJoRpMGgADAQAuAAQKfxQABBAACAmaHv4IAF0CABAACAmaHv4IAF0CAAMABQlsFFhSAPkAAAIAAgkzFtRQAIEAAAAA.Dakarba:BAAALgADCgMJBQAAAA==.Dangmart:BAAALgAECgEJAQAAAA==.Daquilla:BAAALgAECgUJBgAAAA==.Dargonit:BAAALgAECgUJAQAAAA==.Darkisis:BAABLgAECn8eAAIGAAYJTRLNnAA9AQAGAAYJTRLNnAA9AQAAAA==.Darknara:BAABLgAECn8nAAIMAAkJFSAVJQCpAgAMAAkJFSAVJQCpAgAAAA==.Darkterror:BAAALgAECgYJEQABLgAECgYJHgAGAE0SAA==.Darkzy:BAAALgAECgMJAwAAAA==.Darthrayne:BAAALgADCgkJCQAAAA==.Dartol:BAAALgAECgYJBwAAAA==.Dasubertakem:BAAALgAECgQJBgAAAA==.Dawni:BAABLgAECn8aAAITAAYJPSIMDAAQAgATAAYJPSIMDAAQAgAAAA==.',
De='Deathies:BAAALgADCgIJAgAAAA==.Deathigh:BAAALgAECgcJDAAAAA==.Deathjeff:BAAALgAECgkJDgAAAA==.Deathsgates:BAACLgAFFH8FAAIKAAUJvwQ6cADUAAAKAAUJvwQ6cADUAAAuAAQKfy4AAgoACQnTH3ERALsCAAoACQnTH3ERALsCAAEuAAUUBQkbABoAcSQA.Decasia:BAAALgAECggJEwAAAA==.Deheon:BAAALgAECgMJAwAAAA==.Demoswal:BAAALgAECgMJAwAAAA==.Descendent:BAAALgADCgEJAQAAAA==.Destickament:BAAALgADCgMJAwAAAA==.Detala:BAAALgAECgIJAgAAAA==.Detective:BAAALgAECgUJDQAAAA==.Dethkeela:BAABLgAECn8wAAIMAAkJaRsbKQBWAgAMAAkJaRsbKQBWAgABLgAFFAUJCQALAMMHAA==.Dewy:BAABLgAECn8XAAIUAAcJRxAzTQAgAQAUAAcJRxAzTQAgAQAAAA==.',
Dh='Dhfig:BAABLgAECn8kAAIEAAkJOhPvPADJAQAEAAkJOhPvPADJAQAAAA==.',
Di='Dimos:BAAALgAECgYJCwAAAA==.Dinoll:BAAALgAECgYJCQAAAA==.Dinomon:BAAALgAECgMJBgABLgAECgQJBQAPAAAAAA==.Dirtwhistle:BAAALgAECgEJBAAAAA==.Distant:BAAALgAECgEJAQAAAA==.',
Do='Dogo:BAAALgADCgcJEAAAAA==.Doncreenis:BAAALgAECgIJAgAAAA==.',
Dr='Draconnt:BAAALgAECgMJAwABLgAECgQJBQAPAAAAAA==.Dragondh:BAACLgAFFH8LAAIZAAUJPBGYEAAOAQAZAAUJPBGYEAAOAQAuAAQKfy4AAhkACQmNGJcNAD4CABkACQmNGJcNAD4CAAAA.Draksvoid:BAABLgAECn8gAAILAAgJVxr/JQA/AgALAAgJVxr/JQA/AgAAAA==.Dranlu:BAAALgAECgEJAQAAAA==.Dranog:BAABLgAECn8yAAMKAAkJ+RWYMgAIAgAKAAkJ+RWYMgAIAgAXAAIJVQXcXQBVAAAAAA==.Draxol:BAAALgADCgcJEwAAAA==.Drazsi:BAABLgAECn8gAAMWAAYJawYPGwDWAAAWAAYJoAUPGwDWAAAXAAYJwQOWJQB6AAAAAA==.Drovaal:BAAALgADCgEJAQAAAA==.Druidbod:BAAALgAECgUJCAABLgAFFAgJHQABAKobAA==.Drutacular:BAAALgADCgEJAgABLgAECgMJAwAPAAAAAA==.',
Du='Durga:BAAALgAECgYJEgAAAA==.Dusk:BAAALgADCgEJAQABLgAECgEJAQAPAAAAAA==.',
Dy='Dyromancer:BAAALgADCgYJEwAAAA==.',
['Dé']='Défect:BAACLgAFFH8MAAIMAAUJQwSphADvAAAMAAUJQwSphADvAAAuAAQKfxUAAgwABgmYEdObAEkBAAwABgmYEdObAEkBAAAA.',
['Dô']='Dôminic:BAAALgAECgEJAgAAAA==.',
Eb='Ebpindots:BAABLgAECn8cAAMWAAkJqRl+CwCXAQAWAAgJ+Rl+CwCXAQAKAAYJ2xWPhQApAQAAAA==.',
Eg='Eggegg:BAAALgAECgMJBgABLgAECggJKAALAFcbAA==.',
El='Eleanne:BAABLgAECn8mAAMVAAkJ/xLQGwDfAQAVAAkJ/xLQGwDfAQABAAUJeglWkQCJAAAAAA==.Electrico:BAAALgADCgEJAQAAAA==.Elfie:BAAALgAECgEJAQAAAA==.Elfrida:BAAALgADCgIJBAAAAA==.Ellebasi:BAABLgAECn9XAAISAAgJUhkfDAD5AQASAAgJUhkfDAD5AQAAAA==.Elnigteds:BAAALgADCgYJBgAAAA==.',
Em='Emarosa:BAAALgADCgcJBwABLgAECggJHQAYAIIaAA==.Emorya:BAAALgAECgcJCwAAAA==.',
En='Enazen:BAAALgAECgkJEwAAAA==.Enchantz:BAAALgADCgYJBgAAAA==.Endzela:BAAALgADCgUJBQAAAA==.Enky:BAAALgADCgcJCAAAAA==.',
Er='Erlas:BAAALgADCgkJQQAAAA==.Errol:BAAALgAECgEJAQAAAA==.Erui:BAABLgAECn8UAAMFAAYJiRaQKgBoAQAFAAYJiRaQKgBoAQAfAAEJxwK+kAAfAAAAAA==.',
Et='Etrexxig:BAAALgAECgYJBQAAAA==.',
Ev='Evilrayne:BAACLgAFFH8JAAIGAAIJQRepjgClAAAGAAIJQRepjgClAAAuAAQKf0MAAgYACQkXHq0XAMUCAAYACQkXHq0XAMUCAAAA.Evoxus:BAAALgAECgUJCAAAAA==.',
Ex='Exchequer:BAAALgAECgEJAQAAAA==.',
Fa='Faladora:BAAALgAECgEJAQAAAA==.Falimar:BAAALgADCgYJCQAAAA==.Fatherfingur:BAAALgAECgUJCgAAAA==.Fauxpas:BAEBLgAECn8bAAIBAAgJYhcKJQAdAgABAAgJYhcKJQAdAgAAAA==.Fawnzy:BAAALgAECgMJAwAAAA==.',
Fe='Fearoshimâ:BAAALgADCgUJBQAAAA==.Feladrin:BAAALgADCgYJBgAAAA==.Feldommy:BAAALgAECgUJBQAAAA==.Feldritch:BAAALgADCgIJAgAAAA==.Feloak:BAABLgAECn8vAAIgAAkJdxBSDQBxAQAgAAkJdxBSDQBxAQAAAA==.Felonie:BAAALgADCgIJAwAAAA==.Fenyxfall:BAABLgAECn8VAAIEAAYJWhbgagBEAQAEAAYJWhbgagBEAQAAAA==.Feredir:BAABLgAECn8cAAILAAgJWhiVNwD2AQALAAgJWhiVNwD2AQAAAA==.Ferzod:BAAALgADCgEJAQABLgAECggJHQASAMIOAA==.Feyra:BAAALgAECgMJBQAAAA==.',
Fi='Fieryfang:BAABLgAECn8yAAIDAAkJWCMBBgD6AgADAAkJWCMBBgD6AgAAAA==.Firemage:BAAALgAECgcJDgAAAA==.Fireshader:BAAALgADCgEJAQAAAA==.Fishfinger:BAAALgAECgEJAQAAAA==.Fistandilius:BAABLgAECn8VAAIKAAgJnRK7YAB6AQAKAAgJnRK7YAB6AQAAAA==.Fistman:BAACLgAFFH8HAAIeAAIJUyDTJAC5AAAeAAIJUyDTJAC5AAAuAAQKfx4ABB4ACQnKIFYKAJUCAB4ACQnKIFYKAJUCABQAAglYBFlmADkAACEAAQm2FLKHADgAAAAA.',
Fl='Flashsomhash:BAAALgAECgEJAQAAAA==.Flyleaf:BAABLgAECn8hAAMcAAkJcxKeIgC9AQAcAAkJcxKeIgC9AQAdAAEJag7LJQAwAAAAAA==.',
Fo='Foshnu:BAABLgAECn9DAAMiAAkJghTlKwD+AQAiAAkJghTlKwD+AQAJAAYJzAlwWADNAAAAAA==.',
Fr='Fraks:BAAALgADCgMJAwAAAA==.Frostman:BAAALgAECgkJEgAAAA==.Frostymage:BAAALgAECgUJBgAAAA==.Frozandrov:BAABLgAECn8gAAIcAAYJ6AsgQgAVAQAcAAYJ6AsgQgAVAQAAAA==.',
Fu='Fujie:BAABLgAECn8aAAIZAAgJox/zCQDDAgAZAAgJox/zCQDDAgAAAA==.Fujï:BAAALgAECgYJBgAAAA==.Furonfurcrim:BAAALgAECgMJAwAAAA==.Furryfury:BAACLgAFFH8NAAIUAAMJRw6rOgCbAAAUAAMJRw6rOgCbAAAuAAQKfzUAAxQACQk3GB4UAGsCABQACQk3GB4UAGsCAB4ACAnrEH03ABkBAAAA.Fusrodah:BAAALgAFFAMJAwAAAA==.Fuzzyewok:BAABLgAECn8dAAIbAAkJthQeGQAzAgAbAAkJthQeGQAzAgAAAA==.',
['Fë']='Fëlisha:BAAALgADCgQJBAAAAA==.',
Ga='Gaazaura:BAAALgAECgYJBgAAAA==.Gaazmataaz:BAAALgAECgQJCwAAAA==.Galadir:BAAALgADCgEJAQAAAA==.Garag:BAAALgADCgUJBQAAAA==.Garlstedt:BAABLgAECn8dAAISAAUJRxI6JwDQAAASAAUJRxI6JwDQAAAAAA==.Gawdzirra:BAAALgAECgEJAQAAAA==.Gaz:BAAALgAECgcJBwAAAQ==.',
Ge='Geauxaway:BAAALgADCgUJBQAAAA==.Gengar:BAAALgAECgcJCwAAAA==.Genstein:BAAALgADCgIJAgAAAA==.George:BAABLgAECn84AAIjAAkJnwmXGwCuAQAjAAkJnwmXGwCuAQAAAA==.Geostigma:BAAALgADCgEJAQABLgAECgkJMAAGAPscAA==.',
Gh='Ghulrokk:BAAALgAECgYJDAAAAA==.',
Gi='Gilidan:BAAALgAECgIJAgAAAA==.Gizmo:BAAALgAECgQJCAAAAA==.',
Gl='Glenndragon:BAAALgAECggJEwAAAA==.Gluum:BAAALgAECgQJCgAAAA==.',
Go='Goatmeal:BAAALgADCgEJAQAAAA==.Gohi:BAAALgAECgMJAwAAAA==.Gohibasi:BAABLgAECn8ZAAIbAAgJriOKBgAcAwAbAAgJriOKBgAcAwAAAA==.Gormlaif:BAAALgADCgcJCwAAAA==.Gossamerfeet:BAABLgAECn8WAAIFAAgJ3Rb4HwC3AQAFAAgJ3Rb4HwC3AQAAAA==.Gotalian:BAABLgAECn8wAAIRAAkJeApFcgB/AQARAAkJeApFcgB/AQAAAA==.',
Gr='Graceosilver:BAABLgAECn83AAIkAAgJWQRBHAAMAQAkAAgJWQRBHAAMAQAAAA==.Grajademoh:BAAALgADCgcJDAAAAA==.Grajashadow:BAAALgAECgYJDAAAAA==.Gregnor:BAABLgAECn8wAAQlAAkJ1Rv+BQCAAgAlAAkJ1Rv+BQCAAgAVAAMJPxGmXACVAAAmAAEJTgr0cAAnAAAAAA==.Gremöry:BAAALgAECgEJAQAAAA==.Grim:BAABLgAECn8xAAIMAAkJER2MJQBnAgAMAAkJER2MJQBnAgAAAA==.Grippysock:BAAALgAECgQJBgAAAA==.Grover:BAABLgAECn8bAAIRAAkJgg7SYAClAQARAAkJgg7SYAClAQAAAA==.Grozztrak:BAAALgAECgEJAQAAAA==.Grumpybun:BAAALgAECgYJBwAAAA==.Grumpybunbun:BAABLgAECn8tAAIFAAkJKhqaEABVAgAFAAkJKhqaEABVAgAAAA==.',
Gu='Guldrosi:BAABLgAECn8wAAQWAAkJph6VAwBuAgAWAAkJpR6VAwBuAgAKAAcJ+xXCbQBaAQAXAAQJPBEURAClAAAAAA==.',
Gy='Gyat:BAAALgAECgYJEAAAAA==.',
['Gå']='Gårrus:BAABLgAECn9AAAILAAkJcSOqBwAZAwALAAkJcSOqBwAZAwAAAA==.',
Ha='Haarl:BAAALgAECgQJDwAAAA==.Hagel:BAABLgAECn8ZAAIMAAkJ0wxOUgDGAQAMAAkJ0wxOUgDGAQAAAA==.Hairypotter:BAAALgAECgIJAgABLgAECgYJFAAFAIkWAA==.Halazzi:BAAALgAECgEJAwAAAA==.Hallie:BAABLgAECn8xAAIGAAgJRQw7fwB0AQAGAAgJRQw7fwB0AQAAAA==.Hargoose:BAAALgAECgQJBwAAAA==.Harlu:BAABLgAECn9DAAIJAAkJEhBnJgCrAQAJAAkJEhBnJgCrAQAAAA==.Harmwik:BAAALgAECgMJAwABLgAFFAQJDQAFAE4VAA==.Hartbroke:BAABLgAECn9DAAMRAAkJHyBgDwDiAgARAAkJHyBgDwDiAgASAAIJjw97TgAsAAAAAA==.',
He='Helbourne:BAABLgAECn8jAAIZAAgJHyIJCgB7AgAZAAgJHyIJCgB7AgAAAA==.Helfire:BAAALgADCgMJAwAAAA==.Hextraspicy:BAAALgADCgQJBAAAAA==.',
Hi='Hideyoshi:BAAALgAECgEJAQAAAA==.Hijjiup:BAAALgAECgEJAQAAAA==.Hildah:BAAALgAECgIJBQAAAA==.',
Ho='Holliestraza:BAABLgAECn8cAAIiAAgJKhOWVABVAQAiAAgJKhOWVABVAQAAAA==.Holyadrian:BAAALgAECgcJDQAAAA==.Holyfugde:BAAALgADCgQJBQAAAA==.Holyman:BAAALgADCgMJAwAAAA==.Hoof:BAAALgAECgMJAwAAAA==.',
Hw='Hwanwok:BAABLgAECn8mAAMeAAgJbxufFAALAgAeAAgJYBufFAALAgAhAAYJRhbQMwApAQAAAA==.',
Hy='Hyacynth:BAAALgADCgYJBQAAAA==.Hypermage:BAAALgADCgcJBwAAAA==.',
['Hâ']='Hânzö:BAAALgAECgUJEwAAAA==.',
['Hä']='Härbinger:BAAALgAECgUJCQAAAA==.',
Ic='Ic:BAAALgAECgIJAwAAAA==.',
Ig='Ignited:BAAALgADCgYJBwAAAA==.',
Il='Illumine:BAAALgADCgkJDwAAAA==.',
Im='Imadragon:BAABLgAECn8mAAIdAAkJoxO3BgDTAQAdAAkJoxO3BgDTAQAAAA==.Imdeadguy:BAABLgAECn8wAAIQAAkJxCQPAgApAwAQAAkJxCQPAgApAwAAAA==.',
In='Ineedahug:BAAALgAECgkJEAAAAA==.Innalowda:BAAALgADCgcJFAABLgAFFAMJCAACAKEaAA==.',
Ir='Ironhelmhtr:BAABLgAECn8dAAILAAcJeQqifwA0AQALAAcJeQqifwA0AQAAAA==.Irënicus:BAAALgADCgcJCgAAAA==.',
Is='Iseeyounow:BAAALgADCgIJAgAAAA==.Isendra:BAABLgAECn8VAAIGAAcJsgyMnAA9AQAGAAcJsgyMnAA9AQAAAA==.Istian:BAAALgADCgUJBwAAAA==.',
It='Itachi:BAAALgADCgcJGAAAAA==.Itanari:BAAALgADCgUJBQAAAA==.Itiá:BAAALgAECgEJAQAAAA==.',
Ja='Jabtak:BAAALgAECgMJAwAAAA==.Jaded:BAAALgAECgEJAwAAAA==.Janinoo:BAABLgAECn8jAAMfAAkJzgmpLABqAQAfAAkJzgmpLABqAQAFAAEJkAV5hwAoAAAAAA==.Jararth:BAAALgAECgEJBAAAAA==.Jaydrac:BAAALgADCgUJBQABLgAECgcJDwAPAAAAAA==.Jazlee:BAABLgAECn8+AAIQAAkJ4R6oBQCxAgAQAAkJ4R6oBQCxAgAAAA==.',
Je='Jefflock:BAAALgAECgIJAwABLgAECgcJCQAPAAAAAA==.Jeggana:BAAALgAECgIJAwAAAA==.Jezmund:BAAALgAECgYJEAAAAA==.',
Ji='Jinathy:BAABLgAECn8eAAIRAAkJgBJYYACmAQARAAkJgBJYYACmAQAAAA==.Jinnite:BAAALgADCgEJAQAAAA==.Jivek:BAAALgADCgEJAQAAAA==.',
Jo='Jolyñ:BAABLgAECn8wAAIFAAkJyxBlHwC7AQAFAAkJyxBlHwC7AQABLgAECgkJMwAOADoPAA==.',
Ju='Jualygosa:BAABLgAECn8zAAIGAAkJDh69HwCaAgAGAAkJDh69HwCaAgAAAA==.Judgementall:BAACLgAFFH8FAAIbAAIJfCD8LAC8AAAbAAIJfCD8LAC8AAAuAAQKfygAAhsACAn6IEkKAN4CABsACAn6IEkKAN4CAAAA.Juomancito:BAACLgAFFH8KAAIBAAMJ6R5YKQAQAQABAAMJ6R5YKQAQAQAuAAQKfzUAAwEACQmKI9wDAHwDAAEACQmKI9wDAHwDACYACQlSGmkIAFsCAAAA.Justac:BAAALgAECgUJDAABLgAECgYJIAAcAOgLAA==.Justgotbis:BAAALgAECgcJCQAAAA==.',
['Já']='Jáß:BAABLgAFFH8KAAIbAAQJmhb4IAANAQAbAAQJmhb4IAANAQAAAA==.',
['Jä']='Jäb:BAAALgADCgcJBwAAAA==.',
Ka='Kaddrix:BAAALgAECgcJDwAAAA==.Kaldon:BAAALgAECggJEAAAAA==.Kaldonor:BAACLgAFFH8HAAINAAIJoA5OGgCOAAANAAIJoA5OGgCOAAAuAAQKf0AAAg0ACQnbGL4GACYCAA0ACQnbGL4GACYCAAAA.Kalenia:BAACLgAFFH8HAAIiAAIJ3xiSTgCmAAAiAAIJ3xiSTgCmAAAuAAQKf0YAAiIACQmYI8MCAJADACIACQmYI8MCAJADAAAA.Kalvayre:BAABLgAECn8uAAIMAAgJHBULXQCqAQAMAAgJHBULXQCqAQAAAA==.Kanzoorb:BAAALgAECgUJBQAAAA==.Karpana:BAEBLgAECn9EAAMSAAkJOBsQCABNAgASAAgJth0QCABNAgARAAcJLwzRpwAhAQAAAA==.Karrll:BAAALgAECgMJBAAAAA==.Kashir:BAABLgAECn84AAQdAAgJNyLiAQC1AgAdAAgJNyLiAQC1AgATAAcJ6gsfGgAuAQAcAAQJmBqeagCNAAAAAA==.Katamoonfang:BAAALgAECgYJEwAAAA==.Katastrophe:BAAALgAECggJEgAAAA==.Katsumi:BAAALgAECgQJBwAAAA==.Kaythewitch:BAAALgAECgcJCwAAAA==.Kazimirah:BAAALgAECgMJBAAAAA==.Kazrael:BAAALgAECgUJCQAAAA==.',
Ke='Keekat:BAAALgAECggJEwAAAA==.Keloha:BAAALgAECgUJBQAAAA==.Kelvar:BAAALgAECgQJBAAAAA==.Kerpdeath:BAAALgADCgcJCQAAAA==.Kerprage:BAAALgAECgQJDAAAAA==.Kerpredem:BAAALgAECgEJAQAAAA==.Kerpspells:BAAALgADCgcJEgAAAA==.',
Kg='Kgb:BAAALgAECgkJBgAAAA==.Kgosi:BAAALgADCgYJBgAAAA==.',
Kh='Khariaa:BAAALgADCgcJBwAAAA==.Khoravi:BAABLgAECn8gAAIcAAkJtxeCGAALAgAcAAkJtxeCGAALAgAAAA==.',
Ki='Kiamei:BAAALgAECgIJAgAAAA==.Kikora:BAAALgAECgEJAQAAAA==.Kitaska:BAAALgADCgQJAwABLgAECgcJIAAbAFoQAA==.Kittykitty:BAABLgAECn8vAAQiAAkJPRiLHAA1AgAiAAkJPRiLHAA1AgAJAAgJchVrIgDFAQAkAAUJshOpHAAIAQAAAA==.',
Ko='Kolzane:BAACLgAFFH8bAAILAAgJlSQbAAANAgALAAgJlSQbAAANAgAuAAQKfxkAAwsACQl4JHUGACYDAAsACQl4JHUGACYDACcABAnYEDdgAMAAAAAA.Kongfu:BAAALgAECgYJEAAAAA==.Korravah:BAAALgAECgQJBwAAAA==.Koyuki:BAAALgAECgMJBwAAAA==.',
Kr='Kramps:BAAALgAECgQJBgAAAA==.Krandel:BAAALgAECgQJBwAAAA==.Kronan:BAAALgADCgIJAgAAAA==.',
Ku='Kuulas:BAACLgAFFH8JAAILAAMJpxCzWADeAAALAAMJpxCzWADeAAAuAAQKfyUAAgsACQnEHJwUAKQCAAsACQnEHJwUAKQCAAAA.',
Ky='Kynlyn:BAAALgADCgIJAgAAAA==.Kyth:BAABLgAECn85AAISAAkJmRI8EgCYAQASAAkJmRI8EgCYAQAAAA==.Kythlock:BAAALgADCgkJEwABLgAECgkJOQASAJkSAA==.Kythrax:BAAALgAECgEJAQABLgAECgkJOQASAJkSAA==.Kythtok:BAABLgAECn8iAAILAAkJyQtxTgCsAQALAAkJyQtxTgCsAQABLgAECgkJOQASAJkSAA==.',
['Kê']='Kêgstand:BAAALgAECggJEgAAAA==.',
['Kø']='Køda:BAABLgAECn8oAAMBAAkJ7yIaBwA/AwABAAkJ7yIaBwA/AwAVAAYJ0Qx+SgDVAAAAAA==.',
La='Ladycatherin:BAAALgADCgYJCQAAAA==.Ladyhawk:BAAALgADCgYJDAAAAA==.Laquatas:BAAALgAFFAEJAgAAAA==.Lazerbird:BAAALgAECgEJAQAAAA==.',
Le='Leggy:BAAALgAECgIJAgAAAA==.Lela:BAAALgADCgEJAQAAAA==.',
Li='Life:BAAALgAECgEJAgAAAA==.Lifebloomer:BAAALgAECgQJAwABLgAFFAgJMQAYAMYjAA==.Lightnup:BAAALgAECgkJDAAAAA==.Liralyn:BAAALgADCgcJDgAAAA==.Lisanndria:BAAALgADCgUJBQABLgAECgkJJwAMABUgAA==.Lisbet:BAAALgADCgUJBQAAAA==.Litharaldra:BAAALgADCgYJBgAAAA==.Littlehell:BAACLgAFFH8NAAIiAAMJ1xp8DgD2AAAiAAMJ1xp8DgD2AAAuAAQKfx4AAiIACQkqGr0VAGcCACIACQkqGr0VAGcCAAAA.',
Lo='Lokaroki:BAAALgAECgQJBwAAAA==.Lothbrokk:BAAALgAECgUJCAAAAA==.Lothrik:BAAALgADCgIJAgAAAA==.',
Lu='Lucaafer:BAACLgAFFH8RAAIGAAQJdhIBWQAuAQAGAAQJdhIBWQAuAQAuAAQKfykAAgYACQn9HS0zAKYCAAYACQn9HS0zAKYCAAAA.Luda:BAABLgAECn8bAAQWAAkJ2BgwEAArAQAWAAQJahgwEAArAQAKAAUJ5xi8rQDjAAAXAAUJwxM4NQDiAAAAAA==.Lunamoonclaw:BAAALgAECgYJBgAAAA==.',
Ly='Lyssandria:BAABLgAECn81AAIGAAkJeQw7bwCWAQAGAAkJeQw7bwCWAQAAAA==.Lyzoldas:BAABLgAECn8sAAIRAAkJXhh1LgA9AgARAAkJXhh1LgA9AgAAAA==.',
['Lí']='Lília:BAAALgAECgEJAgAAAA==.',
['Lö']='Löwryder:BAABLgAECn8vAAIJAAgJdxFSLQCBAQAJAAgJdxFSLQCBAQAAAA==.',
Ma='Maddera:BAAALgAECgUJCAAAAA==.Madmurdock:BAABLgAECn8XAAMRAAgJKQzslQBRAQARAAgJKQzslQBRAQASAAMJywEDPgBGAAAAAA==.Madness:BAAALgAECgcJDAAAAA==.Maemura:BAAALgAECgcJEwAAAA==.Magîkarp:BAAALgADCgYJBwAAAA==.Mahll:BAAALgAECgQJBwAAAA==.Maiki:BAAALgAECgEJAgAAAA==.Malach:BAAALgAECgcJDAAAAA==.Malchromatus:BAABLgAECn8sAAMTAAkJaxUkCQBRAgATAAkJaxUkCQBRAgAdAAQJKwd3LQCvAAAAAA==.Marcosio:BAAALgAECgUJCAAAAA==.Marsala:BAAALgAECgYJDwAAAA==.Maugan:BAAALgADCgEJAQAAAA==.',
Mb='Mbop:BAAALgAECgQJBAAAAA==.',
Mc='Mcchud:BAAALgAECgEJAQAAAA==.',
Me='Meandragon:BAAALgAECgMJAwAAAA==.Meatyfajita:BAACLgAFFH8KAAIbAAMJ7yNNHgAjAQAbAAMJ7yNNHgAjAQAuAAQKfz4AAhsACQnDJggAAA0EABsACQnDJggAAA0EAAAA.Mechabrew:BAABLgAECn8XAAIhAAcJNQ4zOQARAQAhAAcJNQ4zOQARAQABLgAECgkJLgAgAKAgAA==.Medousa:BAAALgAECgMJAwAAAA==.Megaera:BAABLgAECn8cAAIgAAgJWRzGBQA4AgAgAAgJWRzGBQA4AgAAAA==.Meiko:BAAALgAECgEJAQABLgAECggJHQAYAIIaAA==.Meindblast:BAAALgAECggJDgAAAA==.Meladie:BAAALgAECgMJBAAAAA==.Meladrus:BAAALgADCgEJAQAAAA==.Mellene:BAAALgADCgkJFgAAAA==.Memedecay:BAABLgAECn9KAAMMAAkJUiSKBgBAAwAMAAkJUiSKBgBAAwAYAAMJKh7COACmAAAAAA==.Mememalefic:BAABLgAECn8VAAMfAAkJMxnSDgBlAgAfAAkJMxnSDgBlAgAFAAcJ3xi2HQDLAQABLgAECgkJSgAMAFIkAA==.Mericck:BAAALgADCgMJAwAAAA==.Merlinthos:BAABLgAECn8UAAIGAAgJng02eACDAQAGAAgJng02eACDAQABLgAECgkJQwAaAI0WAA==.Metaljack:BAABLgAECn8wAAIGAAkJ3yW2BgBHAwAGAAkJ3yW2BgBHAwAAAA==.',
Mi='Miasma:BAAALgAECgcJDwABLgAECgMJDwAPAAAAAA==.Midith:BAAALgAECgMJBAAAAA==.Mikethemage:BAAALgAECgEJAQAAAA==.Mikeyboi:BAAALgADCgEJAQAAAA==.Milanesa:BAABLgAECn8aAAIQAAkJYBMsEgDlAQAQAAkJYBMsEgDlAQAAAA==.Mingyue:BAAALgAECgYJEAABLgAFFAMJBQAcAFwEAA==.Mirajåne:BAAALgAECgkJDAABLgAFFAIJAgAPAAAAAA==.Mishaweha:BAABLgAECn8aAAIiAAkJEQ+qNwDFAQAiAAkJEQ+qNwDFAQAAAA==.Mithrandir:BAACLgAFFH8HAAIIAAMJXguPMAC4AAAIAAMJXguPMAC4AAAuAAQKfxYAAggABglGH20XAA4CAAgABglGH20XAA4CAAAA.Mitos:BAABLgAECn82AAIRAAgJuRPPaQCRAQARAAgJuRPPaQCRAQAAAA==.Miyasabi:BAAALgADCgYJBgAAAA==.Mizzet:BAAALgAECgIJAwAAAA==.',
Mo='Modar:BAACLgAFFH8GAAIiAAMJ/BUcQwDLAAAiAAMJ/BUcQwDLAAAuAAQKfyYAAyIACQk/HOYSAKwCACIACQk/HOYSAKwCAAkAAglaGRZtAJMAAAAA.Mojopin:BAAALgAECgYJDAAAAA==.Monkas:BAAALgADCgcJCQAAAA==.Moonpaw:BAAALgAECgEJAQAAAA==.Moonrid:BAAALgAECgEJAQAAAA==.Moonshayd:BAABLgAECn8WAAIVAAcJaA2ZOgAbAQAVAAcJaA2ZOgAbAQAAAA==.Moreann:BAAALgADCgkJEAAAAA==.Morkepo:BAAALgADCgEJAQAAAA==.Morphëus:BAABLgAECn8uAAIGAAcJkhZLaACmAQAGAAcJkhZLaACmAQAAAA==.',
Mu='Muggy:BAAALgADCgIJAgABLgAFFAcJGgAMAKEhAA==.Muha:BAAALgAECgUJBQABLgAECggJEgAPAAAAAA==.Muhalamoon:BAAALgADCgQJBAAAAA==.Murderbot:BAAALgAECgkJCwAAAA==.Murielle:BAAALgADCgUJBQAAAA==.Mushi:BAAALgADCgkJEgAAAA==.Mustardplug:BAAALgADCgEJAQAAAA==.Muzan:BAAALgAECgQJBAAAAA==.Muzzin:BAAALgAECgcJCAAAAA==.',
My='Mystiquebtb:BAAALgAECgkJDAAAAA==.',
['Må']='Måddløck:BAAALgAECgYJDwAAAA==.',
Ne='Needslotion:BAABLgAECn8VAAMdAAYJmBUMDQA0AQAdAAYJJxUMDQA0AQAcAAQJVBJfQADlAAABLgAECggJDgAPAAAAAA==.Neiidra:BAABLgAECn8UAAILAAgJLRciUACnAQALAAgJLRciUACnAQAAAA==.Nepheleah:BAACLgAFFH8bAAIRAAUJmB7wHgB4AQARAAUJmB7wHgB4AQAuAAQKfyUAAhEACQn9IRoQAN0CABEACQn9IRoQAN0CAAAA.Nesinwary:BAAALgAECgEJAQAAAA==.Nesmoth:BAABLgAECn86AAIYAAgJ3CROBQDOAgAYAAgJ3CROBQDOAgAAAA==.Ness:BAAALgAECgcJDwAAAA==.',
Ni='Nifarrow:BAAALgADCgYJBgABLgAECgEJAQAPAAAAAA==.Niiborracho:BAABLgAECn84AAMeAAkJaxc5FAAQAgAeAAkJaxc5FAAQAgAUAAgJIhVDIQABAgAAAA==.Niiko:BAABLgAECn8cAAIiAAUJgiO4LAD5AQAiAAUJgiO4LAD5AQAAAA==.Niisera:BAAALgADCgQJBwAAAA==.Ninhursaga:BAAALgAECgUJBQAAAA==.Nipzfellina:BAAALgAECgEJAQAAAA==.',
No='Norntrox:BAABLgAECn8xAAMEAAkJBhngJwAhAgAEAAkJBhngJwAhAgAgAAEJAACxKQA9AAAAAA==.Nosåj:BAAALgADCgQJBQAAAA==.Nothannah:BAAALgAECgQJBAAAAA==.',
Ns='Nsshaman:BAAALgADCgYJCQAAAA==.',
Nu='Nuadriss:BAAALgAECgQJBAAAAA==.Nunataq:BAAALgADCgEJAQAAAA==.',
Ny='Nylaria:BAAALgADCgUJBQAAAA==.Nyxari:BAAALgAECgYJDwAAAA==.',
Ob='Obscuría:BAAALgADCgYJDQAAAA==.',
Oc='Ochobuun:BAAALgAECgYJCQAAAA==.',
Od='Odrik:BAAALgADCgQJCAAAAA==.',
Ol='Oleana:BAAALgAECgQJBAAAAA==.Oleia:BAAALgAECgYJCQAAAA==.',
On='Onatha:BAAALgADCgkJGgAAAA==.Onaw:BAABLgAECn8aAAImAAcJyxSSFAChAQAmAAcJyxSSFAChAQAAAA==.',
Op='Ops:BAEBLgAECn8fAAMaAAgJjBAFEgD6AAAjAAYJ8xKOKQA9AQAaAAYJagsFEgD6AAAAAA==.',
Or='Orctism:BAAALgADCgIJAgAAAA==.',
Ow='Owlsonatotem:BAABLgAECn8oAAIiAAkJbhhDNQDQAQAiAAkJbhhDNQDQAQAAAA==.',
Ox='Oxymage:BAAALgAECgEJAgAAAA==.',
Pa='Pakno:BAABLgAECn8XAAIRAAkJDBRaWAC5AQARAAkJDBRaWAC5AQAAAA==.Paletia:BAAALgAECgYJBgAAAA==.Pamely:BAABLgAECn8UAAIRAAcJBRfvZAC3AQARAAcJBRfvZAC3AQAAAA==.Pankler:BAAALgAECgEJAwAAAA==.Pavel:BAAALgADCgYJBgAAAA==.',
Pe='Petethelock:BAAALgAECgcJEQAAAA==.Petethemage:BAAALgAECgIJBAAAAA==.',
Ph='Pharmit:BAABLgAECn8rAAQWAAkJliZ2AABCAwAWAAkJ8yV2AABCAwAKAAYJ1iLUPQAVAgAXAAIJ1B5tPADDAAAAAA==.Phayte:BAAALgADCgkJEAAAAA==.Photon:BAAALgADCgYJBQAAAA==.Phrock:BAAALgADCgEJAgAAAA==.',
Pl='Pletua:BAABLgAECn8eAAMjAAgJsyEDEAAjAgAjAAgJLSEDEAAjAgAaAAEJ4SN2HQBnAAAAAA==.',
Po='Pooshy:BAAALgADCgIJAgAAAA==.Porazdir:BAAALgAECgUJBgAAAA==.Porcelayna:BAAALgAECgIJAwABLgAECgkJQwAiAIIUAA==.',
Pr='Primoris:BAAALgADCgUJBQAAAA==.',
Ps='Psion:BAAALgADCgYJBgAAAA==.Psycoorphan:BAAALgADCgYJBgAAAA==.',
Pu='Puds:BAAALgADCgMJAwAAAA==.',
['På']='Påimon:BAAALgADCgIJAgAAAA==.',
Qo='Qorban:BAAALgADCgUJBQAAAA==.',
Qu='Quetzalcoatl:BAAALgAECggJCAAAAA==.Quintin:BAAALgAECgYJBwABLgAFFAQJCQACAGsVAA==.',
Ra='Racavis:BAAALgADCgcJCAAAAA==.Raenisa:BAEALgADCgQJBwABLgAECgkJLgAFAIsYAA==.Ragp:BAAALgAECgMJAwAAAA==.Rainydevil:BAAALgADCgcJDgAAAA==.Rainydevils:BAAALgADCgIJAgAAAA==.Rainymdevil:BAAALgADCgUJBQAAAA==.Rainyxdvl:BAAALgAECgEJAQAAAA==.Rakkel:BAAALgAECgMJAwAAAA==.Ramasey:BAABLgAECn8aAAMaAAgJNhlzBgD5AQAaAAgJNhlzBgD5AQAoAAEJwAyXIgAzAAAAAA==.Rasriann:BAAALgAECgUJBgAAAA==.Ratana:BAAALgAECgYJBgAAAA==.Rawrlordz:BAAALgAECgYJDAAAAA==.',
Re='Reaces:BAAALgADCgEJAQAAAA==.Real:BAABLgAECn8vAAIGAAkJtR/GEwDdAgAGAAkJtR/GEwDdAgABLgAECgYJDwAPAAAAAA==.Reda:BAAALgAECgYJEwAAAA==.Reeality:BAAALgAECgYJDwAAAA==.Reelio:BAAALgAECgQJCAAAAA==.Reikio:BAAALgAECgUJBgAAAA==.Rennala:BAAALgAECgcJCAAAAA==.Repeal:BAAALgAECgQJBAAAAA==.Reptar:BAAALgADCgYJBgABLgAFFAcJHQAhAH4UAA==.Retbet:BAAALgAECgYJDwAAAA==.Revoke:BAABLgAECn8xAAIRAAkJvQ/YUgDHAQARAAkJvQ/YUgDHAQAAAA==.Rexnar:BAAALgAECgEJAgAAAA==.Rexxic:BAAALgAECgEJAgAAAA==.Reyanne:BAEBLgAECn8uAAMFAAkJixiVDACQAgAFAAkJixiVDACQAgAfAAIJnArOawBgAAAAAA==.',
Rh='Rhayn:BAAALgADCgkJEQAAAA==.',
Ro='Rockfish:BAAALgAECgQJBQAAAA==.Rokkhan:BAAALgAECgYJBgAAAA==.Roofio:BAAALgADCgEJAQABLgAFFAMJCAACAKEaAA==.Rootntootn:BAAALgAECgYJBwAAAA==.',
Ru='Rubiroo:BAAALgADCgEJAQAAAA==.Runebellwolf:BAAALgADCgcJCgAAAA==.Ruroni:BAAALgADCggJDwAAAA==.',
Ry='Ryniel:BAABLgAECn80AAILAAkJJhuEFgCWAgALAAkJJhuEFgCWAgAAAA==.Rynitty:BAAALgADCgUJBQABLgAECgcJDQAPAAAAAA==.Rynthia:BAAALgADCgkJCQAAAA==.',
['Ré']='Réira:BAAALgADCgkJEQABLgAFFAMJBQAcAFwEAA==.',
['Rï']='Rïptide:BAAALgAECgUJDQAAAA==.',
Sa='Sabrinalee:BAAALgADCgcJBwAAAA==.Sacremierde:BAAALgAECgYJEQAAAA==.Sagah:BAAALgAECgYJEQAAAA==.Saika:BAAALgADCgkJCQAAAA==.Saintdeamon:BAABLgAECn80AAMBAAkJhhz9JwAJAgABAAgJ1hv9JwAJAgAVAAcJJBKoMQBJAQAAAA==.Sanasta:BAABLgAECn8wAAMKAAgJrxTlSQC3AQAKAAgJlBPlSQC3AQAXAAIJCRnZNgBBAAAAAA==.Sandspur:BAAALgAECgEJAQAAAA==.Sanielin:BAABLgAECn8gAAIhAAcJgyB1GgDKAQAhAAcJgyB1GgDKAQABLgAFFAIJCAAYAPEXAA==.Sanielindk:BAACLgAFFH8IAAIYAAIJ8RfpKwCGAAAYAAIJ8RfpKwCGAAAuAAQKfxkAAhgACQnTIL8EAN4CABgACQnTIL8EAN4CAAAA.Saphìr:BAAALgAECgYJDQAAAA==.Sarahnox:BAAALgAECgcJCAAAAA==.Saramoon:BAABLgAECn84AAMjAAgJyw3GHwCKAQAjAAgJyw3GHwCKAQAaAAQJhgLXFQCdAAAAAA==.Sarda:BAEALgAECggJEAAAAA==.Sargent:BAAALgAECgcJEAAAAA==.Saryaa:BAAALgAECgcJCwAAAA==.Sashchi:BAABLgAECn8ZAAIeAAgJLRKQOwAGAQAeAAgJLRKQOwAGAQAAAA==.Satheronys:BAAALgAECgQJBQAAAA==.',
Sc='Schade:BAAALgAECgQJCQAAAA==.Schrödinger:BAAALgAECgMJAwAAAA==.',
Se='Searen:BAAALgAECgQJBgAAAA==.Sehmet:BAAALgAECgUJCAAAAA==.Seiso:BAABLgAFFH8FAAICAAUJnAkOHwDmAAACAAUJnAkOHwDmAAAAAA==.Seliria:BAABLgAECn8wAAIRAAkJqgpZdQB5AQARAAkJqgpZdQB5AQAAAA==.Senseishifu:BAAALgAECgMJAwAAAA==.Seoulmate:BAAALgAECgUJBQABLgAFFAMJBQAcAFwEAA==.Sephaman:BAAALgAECgEJAQAAAA==.Seprogue:BAAALgADCgcJCgAAAA==.',
Sh='Shadyn:BAAALgAECgEJAQAAAA==.Shadówz:BAAALgADCgEJAQAAAA==.Shandrayn:BAAALgAECgEJAQAAAA==.Sheepstealer:BAAALgADCgQJAwAAAA==.Shiftace:BAAALgAECgQJBgAAAA==.Shiryo:BAABLgAFFH8GAAIMAAIJCwaq4gB9AAAMAAIJCwaq4gB9AAAAAA==.Shockwater:BAAALgAECgUJBwAAAA==.Shotfoot:BAABLgAECn8UAAILAAYJCBs7VgCWAQALAAYJCBs7VgCWAQAAAA==.Shwang:BAABLgAECn8aAAILAAgJXBpwOQDvAQALAAgJXBpwOQDvAQAAAA==.',
Si='Siclock:BAAALgADCgUJBQAAAA==.Sikkerp:BAAALgADCgMJBAAAAA==.Silentio:BAABLgAECn9DAAIaAAkJjRZRBQAdAgAaAAkJjRZRBQAdAgAAAA==.Silihunt:BAAALgADCgMJAwAAAA==.Siliçå:BAAALgADCgYJCQAAAA==.Sinamun:BAABLgAECn8gAAIbAAcJWhC8QwBpAQAbAAcJWhC8QwBpAQAAAA==.Sinandtonic:BAAALgADCgQJBAAAAA==.Sinofwrath:BAACLgAFFH8IAAIEAAMJBxlnUQDqAAAEAAMJBxlnUQDqAAAuAAQKf0AAAgQACQlKJRMCAGQDAAQACQlKJRMCAGQDAAAA.Sinsidious:BAABLgAECn8jAAIMAAgJyQwkdgBwAQAMAAgJyQwkdgBwAQAAAA==.Siwin:BAACLgAFFH8dAAIBAAgJqhvpBACtAgABAAgJqhvpBACtAgAuAAQKfyYAAwEACQm3JMsIAAIDAAEACQm3JMsIAAIDABUABQn8FuFAAP0AAAAA.',
Sk='Skarlett:BAAALgAECgQJBQAAAA==.Skiller:BAAALgADCgYJDAAAAA==.Skinobi:BAAALgAECggJDgAAAA==.Skribb:BAAALgAECgEJAQAAAA==.Skrîbbz:BAAALgAECgEJAQAAAA==.Skysqueezer:BAAALgAECgYJCwAAAA==.',
Sl='Slapchóp:BAABLgAECn8VAAIJAAgJwhp+JwCkAQAJAAgJwhp+JwCkAQAAAA==.',
Sm='Smoko:BAABLgAECn82AAIOAAkJix2mBwChAgAOAAkJix2mBwChAgAAAA==.',
Sn='Snorlax:BAAALgAECgUJBQABLgAECgcJCwAPAAAAAA==.Snowxstorm:BAABLgAECn8uAAIYAAkJXCJSBQDOAgAYAAkJXCJSBQDOAgAAAA==.',
So='Sobieski:BAAALgAFFAIJBAAAAA==.Solae:BAAALgADCgkJDwAAAA==.Solrond:BAAALgAECgYJDQAAAA==.Somemageguy:BAAALgAECgEJAQAAAA==.Souldecay:BAABLgAECn8uAAIMAAkJPBMsPwD/AQAMAAkJPBMsPwD/AQAAAA==.Soultender:BAAALgADCgIJAgAAAA==.Sourdiesel:BAAALgADCgkJCQAAAA==.',
Sp='Spekktrum:BAAALgAECgEJAQAAAA==.Splashzone:BAAALgAECgYJBgAAAA==.Spoonwalk:BAAALgADCgEJAQAAAA==.',
Sq='Squidacles:BAAALgADCgEJAQAAAA==.Squirrly:BAAALgAECgEJAQAAAA==.',
St='Stainedone:BAABLgAECn8dAAIgAAgJsg08EAA6AQAgAAgJsg08EAA6AQAAAA==.Staqua:BAAALgAECggJEQAAAA==.Stateomatter:BAABLgAECn8bAAILAAkJOwtxTQCvAQALAAkJOwtxTQCvAQAAAA==.Steenee:BAAALgAECgUJCgAAAA==.Stevenflowe:BAAALgADCgcJCAAAAA==.Stimpak:BAAALgAECgEJAQAAAA==.Stoneslacher:BAAALgADCgIJBAAAAA==.Streamesance:BAAALgAECgcJDQAAAA==.',
Su='Suanni:BAACLgAFFH8FAAIcAAMJXATpSgCLAAAcAAMJXATpSgCLAAAuAAQKfz8ABBwACQkDFYIaAPoBABwACQkDFYIaAPoBAB0AAglVCGkfAE0AABMAAQmhAAFQAA8AAAAA.Summdari:BAACLgAFFH8MAAIgAAQJog02BwDTAAAgAAQJog02BwDTAAAuAAQKfygAAiAACQm1GToHAAUCACAACQm1GToHAAUCAAAA.Summrot:BAABLgAECn8iAAMKAAkJrxM7SQC5AQAKAAcJsRI7SQC5AQAXAAUJthbQMgDsAAAAAA==.Sunfrostt:BAABLgAECn8VAAIGAAYJVxZ6hQBnAQAGAAYJVxZ6hQBnAQAAAA==.Supplock:BAAALgAECgYJDwAAAA==.Suromeme:BAAALgAECgQJBAABLgAECgkJQwAmAC4gAA==.',
Sw='Swizzler:BAAALgAECgQJBgAAAA==.',
Sy='Sylvalesta:BAAALgAECgUJCAAAAA==.',
Ta='Taedro:BAAALgAECgEJAQAAAA==.Taichung:BAAALgAECgUJAQAAAA==.Talyon:BAABLgAECn8WAAIZAAcJehLFJABBAQAZAAcJehLFJABBAQAAAA==.Tayge:BAAALgADCgEJAQAAAA==.',
Td='Tdogx:BAAALgAECgQJBgAAAA==.',
Te='Teafrog:BAAALgADCgcJBwAAAA==.Tekeeladin:BAAALgAECgEJAQAAAA==.Tekeelà:BAABLgAECn8dAAMLAAgJSCAWJQBDAgALAAgJRyAWJQBDAgAOAAQJJxA3IADeAAABLgAFFAUJCQALAMMHAA==.Tenebris:BAABLgAECn8XAAIRAAYJjxiZgwBzAQARAAYJjxiZgwBzAQAAAA==.Terrorbyte:BAAALgADCgYJBgAAAA==.Terrorhungry:BAAALgAECgcJEwAAAA==.Tessana:BAAALgADCgYJBgAAAA==.',
Th='Thalstrasza:BAABLgAECn80AAIKAAkJfRS1OADxAQAKAAkJfRS1OADxAQAAAA==.Thalör:BAABLgAECn8jAAIVAAgJLBvFHAAbAgAVAAgJLBvFHAAbAgAAAA==.The:BAABLgAECn81AAINAAcJHR7gCADsAQANAAcJHR7gCADsAQAAAA==.Thedevilsown:BAAALgADCgYJDgAAAA==.Thedrizzle:BAABLgAECn8wAAIGAAkJ+xwRKQBwAgAGAAkJ+xwRKQBwAgAAAA==.Thinkwizzle:BAAALgADCgYJBwAAAA==.Thunderthïgh:BAAALgAECgIJAwAAAA==.Thundrfury:BAAALgAECgUJEAAAAA==.',
Ti='Tibalt:BAABLgAECn8TAAIEAAYJUiB2VwCcAQAEAAYJUiB2VwCcAQAAAA==.Tibbles:BAAALgAECgMJBAAAAA==.Tigerlillie:BAAALgADCgIJAgAAAA==.Tipsynips:BAAALgADCgQJBAAAAA==.',
Tk='Tkla:BAAALgADCgIJAgAAAA==.',
Tl='Tlanimass:BAABLgAECn9AAAIQAAkJ+RWyDgDzAQAQAAkJ+RWyDgDzAQAAAA==.',
To='Tommytubstub:BAAALgAECgUJCQAAAA==.Tomstrasza:BAAALgAECgQJBgAAAA==.Tormen:BAABLgAECn9DAAIfAAkJlxd4EgA4AgAfAAkJlxd4EgA4AgAAAA==.Totemforge:BAABLgAECn8kAAMiAAgJgiTcHABaAgAiAAYJtiXcHABaAgAJAAgJfh9CEgBTAgAAAA==.',
Tr='Trapdaddy:BAAALgADCgYJBgAAAA==.Traq:BAAALgADCgQJBAAAAA==.Traydranna:BAAALgAECgEJAQAAAA==.Treeko:BAAALgAFFAIJBAABLgAFFAYJHAAKAFwWAA==.Treston:BAAALgAECgQJBgAAAA==.Treyna:BAAALgAECgYJBgAAAA==.',
Ts='Tsu:BAAALgAECgEJAQAAAA==.Tsyubaki:BAABLgAECn8XAAMUAAkJygsrOgD/AAAUAAkJygsrOgD/AAAeAAEJWAgqgwAtAAAAAA==.',
Tw='Twistdmister:BAAALgADCgUJBAAAAA==.',
Ty='Tydes:BAAALgAECgUJCQAAAA==.Tylenya:BAAALgADCgUJCQAAAA==.Tyrea:BAAALgAECgEJAQAAAA==.Tyrian:BAAALgAECgIJAQABLgAECgMJDwAPAAAAAA==.Tyruak:BAAALgADCgYJBAAAAA==.',
Ul='Uldric:BAAALgAECggJDQAAAA==.',
Un='Undeaddude:BAAALgAECgkJCQAAAA==.Unholybrotha:BAABLgAECn8dAAIYAAgJghpnFADDAQAYAAgJghpnFADDAQAAAA==.Unslayable:BAAALgAECggJEgAAAA==.Unwell:BAABLgAECn8aAAQJAAcJzxF4QgA/AQAJAAcJpxB4QgA/AQAkAAQJahEIHwDgAAAiAAQJgBMffQDZAAAAAA==.',
Ur='Urotherdaddy:BAAALgAECgMJAwABLgAECgYJEQAPAAAAAA==.',
Uz='Uzzy:BAABLgAECn8WAAIgAAYJfQTLHwCRAAAgAAYJfQTLHwCRAAAAAA==.',
Va='Vaevictis:BAAALgAECgQJBwAAAA==.Valandir:BAAALgAFFAIJAwAAAA==.Valazdin:BAAALgAECgkJCQAAAA==.Valenith:BAABLgAECn8aAAIOAAgJNBhgHAC3AQAOAAgJNBhgHAC3AQAAAA==.Valtora:BAAALgAECgUJCwAAAA==.Vartic:BAABLgAECn8UAAITAAYJ9g8bGgAuAQATAAYJ9g8bGgAuAQAAAA==.Vassago:BAAALgAECgUJCAAAAA==.',
Ve='Veliry:BAAALgADCgEJAQAAAA==.Vellarieline:BAABLgAECn8xAAIEAAcJACLSNADoAQAEAAcJACLSNADoAQAAAA==.Velyssara:BAABLgAECn8WAAIEAAYJ2wP0ygCLAAAEAAYJ2wP0ygCLAAAAAA==.Ventor:BAACLgAFFH8JAAImAAMJMSHPCwAiAQAmAAMJMSHPCwAiAQAuAAQKfx4AAyYABwkrIuoOAOYBABUABwnmIaYYAEMCACYABgmDIuoOAOYBAAAA.Veranox:BAAALgAECgYJCAAAAA==.Verbera:BAACLgAFFH8KAAIBAAUJWBptFQCoAQABAAUJWBptFQCoAQAuAAQKfzQAAgEACQmNJO0BALQDAAEACQmNJO0BALQDAAAA.',
Vi='Viduus:BAAALgAECgYJDgAAAA==.Vimah:BAAALgAFFAIJAgABLgAFFAMJBgAMAHkfAA==.Vinton:BAAALgADCgYJBgAAAA==.Vintun:BAAALgADCgIJAgAAAA==.Virdeserti:BAABLgAECn8yAAMFAAkJpyCoBAAvAwAFAAkJpyCoBAAvAwAfAAEJAwcEfAA4AAAAAA==.Visage:BAAALgADCgkJCQAAAA==.Vivian:BAAALgAECgEJAQAAAA==.Vixolot:BAAALgAECgIJAgAAAA==.',
Vl='Vlartank:BAAALgAECgkJBwAAAA==.',
Vm='Vmaoh:BAAALgADCggJCwAAAA==.',
Vo='Voidwithin:BAAALgAECggJEgAAAA==.',
Vu='Vulfox:BAAALgAFFAEJAQAAAA==.Vulpies:BAAALgADCgYJBgAAAA==.',
Vy='Vyketh:BAAALgAECgIJAgABLgAECgkJEgAPAAAAAA==.',
['Vë']='Vëil:BAAALgAECgEJAQAAAA==.',
Wa='Wandiferous:BAAALgAECgYJEwAAAA==.',
We='Webicka:BAAALgAECgUJCgAAAA==.Weezak:BAAALgAECgEJAQAAAA==.',
Wi='Wickedholi:BAAALgAECgEJAQABLgAFFAYJHAAKAFwWAA==.Wickedsmaht:BAACLgAFFH8cAAIKAAYJXBYSJQCXAQAKAAYJXBYSJQCXAQAuAAQKfyQABBcACQnkGVkWAJcBABcABwlYElkWAJcBAAoABwkhGdhuAIMBABYAAQnOGYYtAEMAAAAA.Widowghast:BAAALgADCgQJBAAAAA==.Willowísp:BAABLgAECn84AAIhAAkJohhrDgBKAgAhAAkJohhrDgBKAgAAAA==.Winsfer:BAABLgAECn8UAAImAAgJAB10CgAtAgAmAAgJAB10CgAtAgAAAA==.',
Wn='Wnchester:BAAALgADCgIJAgAAAA==.',
Wo='Woggers:BAAALgAECgYJDQAAAA==.',
Wr='Wrathion:BAABLgAECn8jAAMdAAkJ6BuCAgCNAgAdAAkJ6BuCAgCNAgAcAAMJYwxxWABdAAAAAA==.',
Wu='Wulfenstein:BAAALgADCgUJBQAAAA==.',
Wy='Wyvernman:BAAALgAECgYJCgABLgAECgkJEgAPAAAAAA==.Wywy:BAAALgADCgYJBgAAAA==.',
['Wí']='Wíppy:BAABLgAECn8XAAIeAAgJMSRNBgDgAgAeAAgJMSRNBgDgAgAAAA==.',
Xa='Xalthea:BAABLgAECn8zAAQEAAkJWhQcXwBhAQAEAAgJbRQcXwBhAQAgAAUJng9KHACsAAAZAAIJExJHXwBBAAAAAA==.Xanda:BAACLgAFFH8bAAMaAAUJcSQ9AgCQAQAaAAUJcSQ9AgCQAQAjAAEJxwHvGwBMAAAuAAQKfyIAAhoACAmQH8sBAPkCABoACAmQH8sBAPkCAAAA.Xandahunt:BAAALgAECggJCAABLgAFFAUJGwAaAHEkAA==.Xandk:BAAALgAECgYJBgABLgAFFAUJGwAaAHEkAA==.Xansham:BAAALgAECgUJBQAAAA==.',
Xe='Xenalah:BAAALgAECgIJAgAAAA==.',
Xi='Xikai:BAAALgAFFAEJAQAAAA==.',
Xo='Xobos:BAAALgAECgQJBQAAAA==.',
Xp='Xpddevour:BAABLgAECn83AAIEAAkJURSPPADLAQAEAAkJURSPPADLAQAAAA==.',
Xs='Xscapemystic:BAAALgAECgMJAwAAAA==.Xscapenature:BAAALgAECggJEgAAAA==.',
Xt='Xtena:BAAALgADCgkJDAAAAA==.Xtendron:BAACLgAFFH8VAAMRAAUJ+RSXNQAzAQARAAUJ+RSXNQAzAQAbAAIJrgMEGQB6AAAuAAQKfzIAAxEACQlzIMUaAMkCABEACQlzIMUaAMkCABsABgniB9paABEBAAAA.',
Xu='Xuxo:BAAALgAECgEJAgAAAA==.',
Ya='Yaraxiu:BAAALgAECgcJCwAAAA==.',
Ye='Yegarmiester:BAABLgAECn8eAAIGAAgJZwpLigBeAQAGAAgJZwpLigBeAQAAAA==.Yenti:BAAALgADCggJCgAAAA==.',
Yo='Yodidyoufart:BAACLgAFFH8TAAILAAQJJh9XJQBdAQALAAQJJh9XJQBdAQAuAAQKfy8AAwsACQkIH/ImADoCAAsACQlVHvImADoCACcACAmRFsgmAPMBAAAA.',
Yu='Yuexi:BAAALgAECgQJBAAAAA==.',
Za='Zaco:BAACLgAFFH8FAAIDAAMJog80MQDaAAADAAMJog80MQDaAAAuAAQKfy8AAgMACAl3HysUAEoCAAMACAl3HysUAEoCAAAA.Zae:BAAALgAECgEJAgAAAA==.Zakonn:BAAALgAECgQJBAAAAA==.Zap:BAAALgADCgYJBgABLgAECgcJCwAPAAAAAA==.Zarikas:BAABLgAECn8aAAIEAAgJdRXPSAChAQAEAAgJdRXPSAChAQAAAA==.Zarko:BAAALgAECgEJAQAAAA==.Zatage:BAAALgAECggJDwAAAA==.Zatapatate:BAACLgAFFH8HAAIEAAIJ5RJPcgCKAAAEAAIJ5RJPcgCKAAAuAAQKfzgAAwQACQleHPYeAFECAAQACQlbHPYeAFECACAABgleEugTAAUBAAAA.',
Ze='Zekken:BAAALgADCgUJBwABLgADCgYJCQAPAAAAAA==.Zerality:BAABLgAECn8jAAIRAAkJ/RjnPQADAgARAAkJ/RjnPQADAgAAAA==.',
Zh='Zhachy:BAACLgAFFH8OAAQdAAUJThwdAwBEAQAdAAUJlhkdAwBEAQAcAAMJNRpgPADGAAATAAEJpgVrLAApAAAuAAQKfzcABBwACQnnIhsPAIUCABwACAltIRsPAIUCAB0ACAn+Ii4KADwCABMABAm5FhkcABYBAAAA.',
Zi='Ziggie:BAABLgAECn89AAIEAAkJvyVmAgBeAwAEAAkJvyVmAgBeAwAAAA==.Zinovia:BAACLgAFFH8OAAQeAAQJVB4WCwBkAQAeAAQJVB4WCwBkAQAUAAEJUw0RWQAzAAAhAAEJqQMJWwAxAAAuAAQKfyUABB4ACQmaIcARAGoCAB4ACQmaIcARAGoCABQABwlfGJ4nANYBACEABwlMFhkxAJABAAAA.Ziwei:BAABLgAECn8ZAAMUAAgJcB+YDQC1AgAUAAgJcB+YDQC1AgAeAAUJkgiMUAC5AAABLgAFFAMJBQAcAFwEAA==.',
Zo='Zombieboy:BAAALgAECgcJBgAAAA==.Zookee:BAABLgAECn8pAAIUAAkJRRo1EACSAgAUAAkJRRo1EACSAgAAAA==.Zopilote:BAAALgAECgEJAQAAAA==.',
['Zò']='Zòya:BAAALgAECgQJBAAAAA==.',
['Ðe']='Ðeathguise:BAAALgADCgMJAwAAAA==.',
['Ön']='Önlish:BAAALgAECgEJAQABLgAECgcJDAAPAAAAAA==.Önlîsh:BAAALgADCgMJAwABLgAECgcJDAAPAAAAAA==.',
['ßu']='ßubbleoseven:BAAALgADCgIJAgAAAA==.',
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
