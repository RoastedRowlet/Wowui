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

local lookup = {'Druid-Restoration','Warrior-Arms','Warrior-Fury','Evoker-Augmentation','Priest-Holy','Mage-Frost','Mage-Fire','Priest-Discipline','Warlock-Demonology','DeathKnight-Frost','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Warrior-Protection','Evoker-Preservation','Druid-Balance','Warlock-Affliction','Warlock-Destruction','DeathKnight-Blood','DemonHunter-Devourer','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Monk-Mistweaver','Paladin-Protection','Evoker-Devastation','Shaman-Elemental','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Rogue-Subtlety','Shaman-Enhancement','Druid-Feral','Druid-Guardian','Priest-Shadow','Hunter-Marksmanship','Rogue-Outlaw',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=46,date='2026-05-17',data={Ab='Ababear:BAABLgAECn8fAAIBAAgJnR2bDQDOAgABAAgJnR2bDQDOAgAAAA==.Abardi:BAAALgADCgUJBgAAAA==.',
Ac='Aces:BAAALgAECgIJAgAAAA==.',
Ad='Adeki:BAAALgADCgEJAQAAAA==.',
Ae='Aedaria:BAAALgADCgMJAwAAAA==.Aegis:BAAALgAECgEJAgAAAA==.Aeira:BAAALgADCgYJCQAAAA==.Aelora:BAAALgADCgMJAwAAAA==.Aerenna:BAAALgADCgUJBQAAAA==.',
Ag='Agakk:BAACLgAFFH8OAAICAAQJWB3TCABLAQACAAQJWB3TCABLAQAuAAQKfy8AAgIACQmsI3UCAOACAAIACQmsI3UCAOACAAAA.Agilities:BAAALgAECgQJBAAAAA==.',
Ah='Ahnna:BAAALgADCgkJCAAAAA==.',
Al='Alarrius:BAABLgAECn8iAAMDAAgJWxyyEQApAgADAAgJWxyyEQApAgACAAYJGRCPIQAJAQAAAA==.Albedö:BAAALgAECggJCAABLgAFFAQJCQAEAHoIAA==.Alescia:BAEALgAECgYJBgABLgAECggJJgAFADUaAA==.Alestormia:BAAALgAFFAIJAgAAAA==.Allimental:BAAALgADCgEJAQAAAA==.Allionys:BAABLgAECn8dAAMGAAgJNSS8FACsAgAGAAgJNSS8FACsAgAHAAEJyhnUCwBJAAAAAA==.Alorelia:BAAALgADCgUJBQAAAA==.Aloris:BAABLgAECn8XAAMIAAgJISL8EgD/AQAIAAgJBSH8EgD/AQAFAAUJNwpNSwALAQAAAA==.Alyêska:BAAALgAECgYJCAAAAA==.',
Am='Amanises:BAAALgAECgcJDgAAAA==.Amilara:BAAALgAECgUJCQAAAA==.',
An='Ananaya:BAAALgAECgUJCQABLgAECgcJIwAJAMsSAA==.Andinestiri:BAAALgAECggJDgAAAA==.Andolastrasz:BAAALgADCgEJAQAAAA==.Andy:BAAALgAECgEJAgAAAA==.Aneethea:BAAALgADCgYJBgAAAA==.Anniklynn:BAAALgADCgIJAgAAAA==.Antaric:BAAALgAECgUJCAAAAA==.Anyalem:BAAALgAECgEJAQAAAA==.',
Ao='Ao:BAAALgAECgYJBgAAAA==.',
Ap='Apotic:BAABLgAECn8iAAIKAAkJ8gj4CQB2AQAKAAkJ8gj4CQB2AQAAAA==.Apuntar:BAAALgADCgYJCwAAAA==.',
Aq='Aquamaree:BAAALgAECgYJCwAAAA==.Aquamyth:BAAALgADCgMJAwAAAA==.Aquilla:BAACLgAFFH8LAAMLAAUJcwaXQgDCAAAMAAMJ6AVBFwDTAAALAAQJRQeXQgDCAAAuAAQKfyAAAwwACAkWGTUMAAwCAAwACAmFFzUMAAwCAAsABgmBG8phAEIBAAAA.',
Ar='Archenea:BAAALgAECgMJAwAAAA==.Archenore:BAABLgAECn8XAAIDAAcJagdNVQBWAQADAAcJagdNVQBWAQAAAA==.Ariisa:BAAALgAECgUJBwAAAA==.Arkify:BAAALgADCgYJBgAAAA==.Armadyl:BAAALgAECgEJAQABLgAECgQJBwANAAAAAA==.Around:BAAALgAECgMJAwAAAA==.Arrancar:BAAALgAECgYJCAAAAA==.Arrianda:BAAALgADCgQJBAAAAA==.',
As='Ashw:BAABLgAECn8XAAIOAAcJURS7GQApAQAOAAcJURS7GQApAQAAAA==.Aslann:BAAALgAECgcJCAAAAA==.Asukka:BAAALgAECgcJEQAAAA==.Asëya:BAAALgAECgMJBQAAAA==.',
At='Atomique:BAACLgAFFH8cAAIPAAUJrhS2DQBeAQAPAAUJrhS2DQBeAQAuAAQKf0QAAg8ACAkXH9YGANMCAA8ACAkXH9YGANMCAAAA.Attenborough:BAAALgAECgUJBgABLgAECgYJDwANAAAAAA==.',
Au='Auggie:BAAALgADCgEJAQAAAA==.',
Av='Avalíne:BAAALgADCgUJBQAAAA==.Avesa:BAAALgAECgQJCAAAAA==.Avoidant:BAABLgAECn8VAAMBAAgJwBRXMgCZAQABAAgJwBRXMgCZAQAQAAEJogqucAAsAAAAAA==.',
Ay='Aydir:BAAALgADCgUJBwAAAA==.Aylithe:BAAALgAECgQJBQAAAA==.',
Az='Azanadra:BAAALgAECgQJBwAAAA==.Azazell:BAAALgAECgQJBQAAAA==.Azenea:BAABLgAECn8fAAQRAAgJBgavDQBZAQARAAgJRwWvDQBZAQAJAAIJhwG0IAEwAAASAAEJ5AjjNQAjAAAAAA==.',
Ba='Baculum:BAABLgAECn8aAAITAAgJZBghFQB5AQATAAgJZBghFQB5AQAAAA==.Bacõn:BAAALgAECgQJBAAAAA==.Badmoonrisin:BAAALgAECgMJAwAAAA==.Bainne:BAAALgAECgQJCAAAAA==.Ballzach:BAABLgAECn8cAAIIAAYJqh5CJABeAQAIAAYJqh5CJABeAQABLgAFFAcJJAATAMUjAA==.Bazookabob:BAAALgAECgYJEgABLgAECgQJBAANAAAAAA==.',
Be='Beangles:BAAALgAECgEJAQAAAA==.Bearlylegal:BAAALgAECgYJBgABLgAECgkJBwANAAAAAA==.Becky:BAAALgAECgMJBgABLgAECgkJGwAUAIgVAA==.Beekyy:BAABLgAECn8bAAIUAAkJiBV1OACmAQAUAAkJiBV1OACmAQAAAA==.Belenova:BAAALgAECgUJBgAAAA==.Bellapearl:BAAALgAECgMJBgAAAA==.Berkyn:BAAALgADCgMJAwAAAA==.Beverly:BAAALgAECgEJAQAAAA==.',
Bi='Bittydrood:BAAALgAECgEJAQAAAA==.Bittylexis:BAAALgAECgYJDwAAAA==.',
Bl='Blakheart:BAABLgAECn8xAAIVAAkJjRXtBAD5AQAVAAkJjRXtBAD5AQAAAA==.Bleuopal:BAAALgADCgcJDAAAAA==.Blueaxle:BAABLgAECn8qAAMWAAkJnBclFAAtAgAWAAkJnBclFAAtAgAXAAIJpgHNMQFAAAAAAA==.Blur:BAAALgAECgcJDQAAAA==.Bluzzy:BAAALgAECgQJBQABLgAECgkJFwAGAIQbAA==.Blèu:BAABLgAECn8fAAIYAAkJOhAAHQDFAQAYAAkJOhAAHQDFAQAAAA==.',
Bo='Boomdoom:BAAALgAECgQJBAAAAA==.Bootycat:BAAALgADCgcJBwABLgADCgkJCgANAAAAAA==.Bouffenièce:BAAALgAECgQJBwAAAA==.Boufsy:BAAALgADCgkJEQAAAA==.',
Br='Brakii:BAAALgAECgIJAgAAAA==.Breathe:BAACLgAFFH8HAAIBAAMJnBIOKQDZAAABAAMJnBIOKQDZAAAuAAQKfxoAAwEABwkPHoYfAA4CAAEABwkPHoYfAA4CABAAAQlADzZrADQAAAAA.Brewballs:BAABLgAECn8qAAIYAAgJpwpVMwAnAQAYAAgJpwpVMwAnAQAAAA==.Brynarra:BAAALgADCgUJBQAAAA==.',
Bu='Bubbletea:BAAALgAECgQJDgAAAA==.Bunnicula:BAABLgAECn8lAAMRAAkJsxhxBwDcAQARAAgJfhtxBwDcAQAJAAUJ5QkrkQDqAAAAAA==.',
Bw='Bwanga:BAAALgAECgYJDwAAAA==.',
['Bö']='Böömer:BAAALgAECgQJCgAAAA==.',
Ca='Calmac:BAACLgAFFH8FAAIYAAMJbwaFJACkAAAYAAMJbwaFJACkAAAuAAQKfxYAAhgABgnFG+8bAM8BABgABgnFG+8bAM8BAAAA.Cameron:BAAALgAECgYJDAAAAA==.Capetonrex:BAAALgAECgEJAQAAAA==.Cavall:BAAALgAECgMJAwAAAA==.Caythus:BAACLgAFFH8IAAMSAAMJiB78EABeAAAJAAIJ8xtUaQCkAAASAAEJsCP8EABeAAAuAAQKfxYAAxIABwnhJLsLAAYCABIABQkPJLsLAAYCAAkABQnmIhNRANUBAAAA.',
Ce='Celeana:BAAALgAECgYJDwAAAA==.Celeleron:BAAALgADCgcJBwAAAA==.Celencia:BAAALgAECgcJCgAAAA==.',
Ch='Chadmcguffin:BAABLgAECn8ZAAIZAAkJHCJqCABSAgAZAAkJHCJqCABSAgAAAA==.Chaelin:BAAALgAECgcJBgAAAA==.Chakabad:BAAALgAECgYJEAAAAA==.Chalgar:BAAALgAECgMJBAAAAA==.Chaosblossom:BAAALgADCgYJBwAAAA==.Cheezeballs:BAAALgADCgEJAQABLgAFFAEJAQANAAAAAA==.Chenahala:BAAALgAECgYJEgAAAA==.Chibeard:BAAALgAECgkJBwAAAA==.Chåni:BAAALgAECgYJEwAAAA==.',
Ci='Ciege:BAABLgAECn8iAAMaAAkJ4xIMCwAvAQAEAAgJrhCUKABaAQAaAAYJABIMCwAvAQAAAA==.Cinrah:BAABLgAFFH8LAAIUAAYJdRGsFQCEAQAUAAYJdRGsFQCEAQAAAA==.',
Cl='Cloudwalker:BAAALgADCgkJCwAAAA==.',
Co='Coffeelatte:BAAALgAECgEJAQAAAA==.Complainz:BAAALgAECgEJAQAAAA==.Conanascus:BAAALgAECgMJBAABLgAECgkJMAAVAMEUAA==.Concinnat:BAAALgADCgUJBQAAAA==.Confessorr:BAAALgADCgYJBgAAAA==.Cosantóir:BAAALgAECgUJBgAAAA==.',
Cr='Crispysock:BAAALgAECggJEQAAAA==.Croda:BAAALgAECgYJDAAAAA==.Crowe:BAAALgAECgIJAwAAAA==.Cröno:BAAALgAECgYJDAAAAA==.',
Cu='Cursez:BAABLgAECn8XAAIJAAYJYxO1cQApAQAJAAYJYxO1cQApAQABLgAFFAYJHQAbAFEhAA==.',
Cy='Cylndra:BAAALgADCgcJBwAAAA==.Cynderr:BAAALgAECgUJCAAAAA==.',
['Cè']='Cèrc:BAAALgAECgIJAwAAAA==.',
Da='Daemian:BAAALgAECgcJDAABLgAECgkJGQAZABwiAA==.Dakarba:BAAALgADCgMJBQAAAA==.Daquilla:BAAALgAECgUJBgAAAA==.Dargonit:BAAALgAECgUJAQAAAA==.Darkisis:BAABLgAECn8ZAAIGAAYJaA8xkwAhAQAGAAYJaA8xkwAhAQAAAA==.Darknara:BAABLgAECn8mAAIcAAkJUx8VJQCpAgAcAAkJUx8VJQCpAgAAAA==.Darkterror:BAAALgAECgYJDAABLgAECgYJGQAGAGgPAA==.Darkzy:BAAALgAECgMJAwAAAA==.Dartol:BAAALgAECgIJAgAAAA==.Dasubertakem:BAAALgAECgQJBgAAAA==.Dawni:BAABLgAECn8YAAIPAAYJPSJUCQAVAgAPAAYJPSJUCQAVAgAAAA==.',
De='Deathies:BAAALgADCgIJAgAAAA==.Deathigh:BAAALgAECgcJDAAAAA==.Deathjeff:BAAALgAECgkJDgAAAA==.Deathsgates:BAABLgAECn8lAAIJAAgJrR/7HgCdAgAJAAgJrR/7HgCdAgABLgAFFAUJEwAVAJgiAA==.Decasia:BAAALgAECgYJDgAAAA==.Deheon:BAAALgADCgQJBgAAAA==.Demoswal:BAAALgADCgEJAgAAAA==.Descendent:BAAALgADCgEJAQAAAA==.Destickament:BAAALgADCgMJAwAAAA==.Detala:BAAALgAECgIJAgAAAA==.Detective:BAAALgAECgUJDQAAAA==.Dethkeela:BAABLgAECn8tAAIcAAkJaRvDHABiAgAcAAkJaRvDHABiAgABLgAFFAUJCQALAMMHAA==.Dewy:BAABLgAECn8XAAIYAAcJRxAtNQAdAQAYAAcJRxAtNQAdAQAAAA==.',
Dh='Dhfig:BAABLgAECn8kAAIUAAkJORO+LgDPAQAUAAkJORO+LgDPAQAAAA==.',
Di='Dimos:BAAALgAECgUJBQAAAA==.Dinoll:BAAALgAECgYJCQAAAA==.Dinomon:BAAALgAECgMJAwABLgAECgQJBQANAAAAAA==.Dirtwhistle:BAAALgAECgEJBAAAAA==.',
Do='Dogo:BAAALgADCgcJEAAAAA==.',
Dr='Draconnt:BAAALgAECgMJAwABLgAECgQJBQANAAAAAA==.Dragondh:BAABLgAECn8rAAIdAAgJVhfUEwA1AgAdAAgJVhfUEwA1AgAAAA==.Draksvoid:BAABLgAECn8UAAILAAcJihNLSQB8AQALAAcJihNLSQB8AQAAAA==.Dranlu:BAAALgAECgEJAQAAAA==.Dranog:BAABLgAECn8oAAMJAAgJlha/RgCVAQAJAAgJlha/RgCVAQASAAIJVQXcXQBVAAAAAA==.Draxol:BAAALgADCgcJEwAAAA==.Drazsi:BAABLgAECn8UAAMSAAYJ3gTZHQCEAAARAAUJ0APHGACSAAASAAYJwQPZHQCEAAAAAA==.Drovaal:BAAALgADCgEJAQAAAA==.Druidbod:BAAALgAECgUJCAABLgAFFAYJGQABAFodAA==.Drutacular:BAAALgADCgEJAgAAAA==.',
Du='Durga:BAAALgAECgYJEgAAAA==.Dusk:BAAALgADCgEJAQABLgAECgEJAQANAAAAAA==.',
Dy='Dyromancer:BAAALgADCgYJEwAAAA==.',
['Dé']='Défect:BAACLgAFFH8HAAIcAAQJAgLtZADyAAAcAAQJAgLtZADyAAAuAAQKfxUAAhwABgmYEdObAEkBABwABgmYEdObAEkBAAAA.',
['Dô']='Dôminic:BAAALgAECgEJAgAAAA==.',
Eb='Ebpindots:BAABLgAECn8ZAAMRAAgJ2BpSCwBLAQARAAcJZxtSCwBLAQAJAAYJ2xXxbAAzAQAAAA==.',
Eg='Eggegg:BAAALgAECgMJBgABLgAECggJKAALAFcbAA==.',
El='Eleanne:BAABLgAECn8eAAMQAAgJlwyuKQA3AQAQAAgJlwyuKQA3AQABAAUJdwl3fQCJAAAAAA==.Elfrida:BAAALgADCgIJBAAAAA==.Ellebasi:BAABLgAECn80AAIZAAgJfhI3EgBXAQAZAAgJfhI3EgBXAQAAAA==.',
Em='Emarosa:BAAALgADCgcJBwABLgAECggJHQATAIEaAA==.Emorya:BAAALgAECgcJCwAAAA==.',
En='Enazen:BAAALgAECggJDwAAAA==.Enchantz:BAAALgADCgYJBgAAAA==.Endzela:BAAALgADCgUJBQAAAA==.Enky:BAAALgADCgcJCAAAAA==.',
Er='Erlas:BAAALgADCgkJOAAAAA==.Errol:BAAALgAECgEJAQAAAA==.Erui:BAAALgAECgYJEgAAAA==.',
Ev='Evilrayne:BAABLgAECn8wAAIGAAkJ9hhUKABAAgAGAAkJ9hhUKABAAgAAAA==.Evoxus:BAAALgAECgUJCAAAAA==.',
Ex='Exchequer:BAAALgAECgEJAQAAAA==.',
Fa='Fatherfingur:BAAALgAECgUJDQAAAA==.Fauxpas:BAEBLgAECn8bAAIBAAgJYRePHQAdAgABAAgJYRePHQAdAgAAAA==.Fawnzy:BAAALgAECgMJAwAAAA==.',
Fe='Fearoshimâ:BAAALgADCgUJBQAAAA==.Feladrin:BAAALgADCgYJBgAAAA==.Feldommy:BAAALgAECgUJBQAAAA==.Feloak:BAABLgAECn8pAAIeAAkJvw8kCgB7AQAeAAkJvw8kCgB7AQAAAA==.Felonie:BAAALgADCgIJAwAAAA==.Fenyxfall:BAAALgAECgQJDwAAAA==.Feredir:BAAALgAECgYJDQAAAA==.Ferzod:BAAALgADCgEJAQABLgAECggJGgAZAAcMAA==.',
Fi='Fieryfang:BAABLgAECn8tAAIDAAkJhCKlBADqAgADAAkJhCKlBADqAgAAAA==.Fireshader:BAAALgADCgEJAQAAAA==.Fishfinger:BAAALgADCgEJAQAAAA==.Fistandilius:BAABLgAECn8VAAIJAAgJnRKITQCBAQAJAAgJnRKITQCBAQAAAA==.Fistman:BAABLgAECn8cAAQfAAkJoyDjBgChAgAfAAkJoyDjBgChAgAgAAEJthTocwA5AAAYAAIJWARZZgA5AAAAAA==.',
Fl='Flashsomhash:BAAALgAECgEJAQAAAA==.Flyleaf:BAABLgAECn8gAAMEAAkJcBIHGgDCAQAEAAkJcBIHGgDCAQAaAAEJag5LHgA0AAAAAA==.',
Fo='Foshnu:BAABLgAECn8qAAMhAAgJOg+KQgBRAQAhAAgJOg+KQgBRAQAbAAUJLQdMVACfAAAAAA==.',
Fr='Fraks:BAAALgADCgMJAwAAAA==.Frostman:BAAALgAECgQJCgABLgAECgYJCgANAAAAAA==.Frostymage:BAAALgADCgQJBQAAAA==.Frozandrov:BAABLgAECn8WAAIEAAQJ9AzPSwC1AAAEAAQJ9AzPSwC1AAABLgAECgUJCgANAAAAAA==.',
Fu='Fujie:BAABLgAECn8aAAIdAAgJox/zCQDDAgAdAAgJox/zCQDDAgAAAA==.Fujï:BAAALgAECgYJBgAAAA==.Furious:BAAALgADCgMJAwAAAA==.Furonfurcrim:BAAALgAECgMJAwAAAA==.Furryfury:BAACLgAFFH8MAAIYAAMJRw56IQC6AAAYAAMJRw56IQC6AAAuAAQKfyQAAxgACAnlFlAZAOgBABgACAnlFlAZAOgBAB8ABQnbCZpOANgAAAAA.Fuzzyewok:BAABLgAECn8WAAIWAAkJRQ7IIQC2AQAWAAkJRQ7IIQC2AQAAAA==.',
['Fë']='Fëlisha:BAAALgADCgQJBAAAAA==.',
Ga='Gaazaura:BAAALgAECgYJBgAAAA==.Gaazmataaz:BAAALgAECgQJCwAAAA==.Galadir:BAAALgADCgEJAQAAAA==.Garag:BAAALgADCgUJBQAAAA==.Garlstedt:BAAALgAECgUJEwAAAA==.Gawdzirra:BAAALgADCgIJAgAAAA==.',
Ge='Gengar:BAAALgAECgQJBAAAAA==.Genstein:BAAALgADCgIJAgAAAA==.George:BAABLgAECn8eAAIiAAgJLAcEIABFAQAiAAgJLAcEIABFAQAAAA==.Geostigma:BAAALgADCgEJAQABLgAECgkJIQAGAMscAA==.',
Gh='Ghulrokk:BAAALgAECgYJDAAAAA==.',
Gi='Gilidan:BAAALgAECgIJAgAAAA==.Gizmo:BAAALgAECgEJAQAAAA==.',
Gl='Glenndragon:BAAALgAECgcJDwAAAA==.Gluum:BAAALgAECgQJCAAAAA==.',
Go='Goatmeal:BAAALgADCgEJAQAAAA==.Gohi:BAAALgADCgkJCQAAAA==.Gohibasi:BAAALgAECgYJDQAAAA==.Gormlaif:BAAALgADCgUJBQAAAA==.Gossamerfeet:BAAALgAECgYJDwAAAA==.Gotalian:BAABLgAECn8nAAIXAAkJmgmdXgB3AQAXAAkJmgmdXgB3AQAAAA==.',
Gr='Graceosilver:BAABLgAECn8jAAIjAAcJCwOcGADSAAAjAAcJCwOcGADSAAAAAA==.Grajademoh:BAAALgADCgcJDAAAAA==.Grajashadow:BAAALgAECgYJDAAAAA==.Gregnor:BAABLgAECn8pAAQkAAkJAxltBABzAgAkAAkJ8hhtBABzAgAQAAMJPxG5SQCcAAAlAAEJTgpuSQApAAAAAA==.Gremöry:BAAALgAECgEJAQAAAA==.Grim:BAABLgAECn8nAAIcAAkJGBqPLwAGAgAcAAkJGBqPLwAGAgAAAA==.Grippysock:BAAALgAECgEJAQAAAA==.Grover:BAAALgAECgcJEAAAAA==.Grozztrak:BAAALgADCgQJBAAAAA==.Grumpybun:BAAALgAECgYJBgAAAA==.Grumpybunbun:BAABLgAECn8lAAIFAAkJOBlEEwACAgAFAAkJOBlEEwACAgAAAA==.',
Gu='Guldrosi:BAABLgAECn8pAAQRAAkJ5hu3AgBIAgARAAkJ5Bu3AgBIAgAJAAcJ9RWOWwBbAQASAAQJPBEURAClAAAAAA==.',
Gy='Gyat:BAAALgAECgYJEAAAAA==.',
['Gå']='Gårrus:BAABLgAECn8oAAILAAgJ/SGSEwB1AgALAAgJ/SGSEwB1AgAAAA==.',
Ha='Haarl:BAAALgAECgQJDwAAAA==.Hagel:BAAALgAECgkJEQAAAA==.Hairypotter:BAAALgADCgMJAwAAAA==.Halazzi:BAAALgAECgEJAQAAAA==.Hallie:BAABLgAECn8kAAIGAAcJsgunggA+AQAGAAcJsgunggA+AQAAAA==.Hargoose:BAAALgAECgMJBQAAAA==.Harlu:BAABLgAECn8qAAIbAAgJiQcvOAAMAQAbAAgJiQcvOAAMAQAAAA==.Hartbroke:BAABLgAECn8qAAMXAAgJpRwuIgBCAgAXAAgJpRwuIgBCAgAZAAIJjw/5PQAtAAAAAA==.',
He='Helbourne:BAABLgAECn8dAAIdAAgJHSI8BgCPAgAdAAgJHSI8BgCPAgAAAA==.Hextraspicy:BAAALgADCgQJBAAAAA==.',
Hi='Hideyoshi:BAAALgAECgEJAQAAAA==.Hijjiup:BAAALgAECgEJAQAAAA==.Hildah:BAAALgAECgIJBQAAAA==.',
Ho='Holliestraza:BAABLgAECn8cAAIhAAgJKhPmQABXAQAhAAgJKhPmQABXAQAAAA==.Holyadrian:BAAALgAECgcJCQAAAA==.Holyfugde:BAAALgADCgQJBQAAAA==.Holyman:BAAALgADCgMJAwAAAA==.Hoof:BAAALgAECgMJAwAAAA==.',
Hw='Hwanwok:BAABLgAECn8gAAMfAAgJ6hpfEAADAgAfAAgJ2xpfEAADAgAgAAYJRhZVKgAwAQAAAA==.',
Hy='Hyacynth:BAAALgADCgYJBQAAAA==.Hypermage:BAAALgADCgcJBwAAAA==.',
['Hâ']='Hânzö:BAAALgAECgUJEwAAAA==.',
['Hä']='Härbinger:BAAALgAECgUJCQAAAA==.',
Ic='Ic:BAAALgAECgIJAgAAAA==.',
Ig='Ignited:BAAALgADCgYJBwAAAA==.',
Il='Illumine:BAAALgADCggJDgAAAA==.',
Im='Imadragon:BAABLgAECn8lAAIaAAkJ0RKrBADuAQAaAAkJ0RKrBADuAQAAAA==.Imdeadguy:BAABLgAECn8lAAIOAAkJjCMuAgAAAwAOAAkJjCMuAgAAAwAAAA==.',
In='Ineedahug:BAAALgAECgcJBwAAAA==.Innalowda:BAAALgADCgcJEQABLgAECgkJGQAZABwiAA==.',
Ir='Ironhelmhtr:BAAALgAECgYJEAAAAA==.Irënicus:BAAALgADCgcJCgAAAA==.',
Is='Iseeyounow:BAAALgADCgIJAgAAAA==.Isendra:BAABLgAECn8VAAIGAAcJsgxKhAA7AQAGAAcJsgxKhAA7AQAAAA==.Istian:BAAALgADCgQJBAAAAA==.',
It='Itachi:BAAALgADCgcJGAAAAA==.Itiá:BAAALgADCgUJBgAAAA==.',
Ja='Jabtak:BAAALgAECgMJAwAAAA==.Jaded:BAAALgAECgEJAwAAAA==.Janinoo:BAABLgAECn8VAAMmAAcJBQjKMwAEAQAmAAcJBQjKMwAEAQAFAAEJkAV5hwAoAAAAAA==.Jararth:BAAALgAECgEJBAAAAA==.Jazlee:BAABLgAECn8lAAIOAAgJRR3PCQAYAgAOAAgJRR3PCQAYAgAAAA==.',
Je='Jefflock:BAAALgAECgIJAgABLgAECgYJBwANAAAAAA==.Jeggana:BAAALgAECgEJAQAAAA==.Jezmund:BAAALgADCggJCAAAAA==.',
Ji='Jinathy:BAABLgAECn8dAAIXAAgJLhLeXgB3AQAXAAgJLhLeXgB3AQAAAA==.Jinnite:BAAALgADCgEJAQAAAA==.',
Jo='Jolyñ:BAABLgAECn8wAAIFAAkJyxARFwDXAQAFAAkJyxARFwDXAQABLgAECgkJMAAMADoPAA==.',
Ju='Jualygosa:BAABLgAECn8zAAIGAAkJDx5zFACuAgAGAAkJDx5zFACuAgAAAA==.Judgementall:BAABLgAECn8bAAIWAAgJFyDhBwDTAgAWAAgJFyDhBwDTAgAAAA==.Juomancito:BAABLgAECn8kAAIBAAkJiCOvAgB9AwABAAkJiCOvAgB9AwAAAA==.Justac:BAAALgAECgUJCgAAAA==.Justgotbis:BAAALgAECgYJBwAAAA==.',
['Já']='Jáß:BAABLgAFFH8KAAIWAAQJmhaqFQAwAQAWAAQJmhaqFQAwAQAAAA==.',
['Jä']='Jäb:BAAALgADCgcJBwAAAA==.',
Ka='Kaddrix:BAAALgAECgcJDwAAAA==.Kaldonor:BAABLgAECn82AAIKAAkJkxa7BAAZAgAKAAkJkxa7BAAZAgAAAA==.Kalenia:BAABLgAECn81AAIhAAkJOSLoAgBcAwAhAAkJOSLoAgBcAwAAAA==.Kalvayre:BAABLgAECn8mAAIcAAgJthT3VgCIAQAcAAgJthT3VgCIAQAAAA==.Kanzoorb:BAAALgAECgUJBQAAAA==.Karpana:BAEBLgAECn8uAAMZAAcJhRrkCwC7AQAZAAcJhRrkCwC7AQAXAAUJWQ68uQDSAAAAAA==.Kashir:BAABLgAECn8kAAQaAAcJwyFdAwAuAgAaAAcJwyFdAwAuAgAEAAQJmBrNVQCPAAAPAAIJhQ2JMAA1AAAAAA==.Katamoonfang:BAAALgAECgYJDQAAAA==.Katastrophe:BAAALgAECggJEgAAAA==.Katsumi:BAAALgAECgQJBwAAAA==.Kaythewitch:BAAALgAECgUJBQAAAA==.Kazimirah:BAAALgAECgEJAQAAAA==.Kazrael:BAAALgAECgMJBQAAAA==.',
Ke='Keekat:BAAALgAECggJCwAAAA==.Keloha:BAAALgAECgUJBQAAAA==.Kerpdeath:BAAALgADCgcJBwAAAA==.Kerprage:BAAALgAECgQJCgAAAA==.Kerpredem:BAAALgAECgEJAQAAAA==.Kerpspells:BAAALgADCgcJEgAAAA==.',
Kh='Khariaa:BAAALgADCgcJBwAAAA==.Khoravi:BAABLgAECn8aAAIEAAkJbRZ5FwDbAQAEAAkJbRZ5FwDbAQAAAA==.',
Ki='Kikora:BAAALgAECgEJAQAAAA==.Kitaska:BAAALgADCgQJAwABLgAECgcJGwAWAFoQAA==.Kittykitty:BAABLgAECn8nAAMhAAkJPRiLHAA1AgAhAAkJPRiLHAA1AgAjAAUJshMiFAAOAQAAAA==.',
Ko='Kolzane:BAACLgAFFH8TAAILAAcJriMbAAANAgALAAcJriMbAAANAgAuAAQKfxkAAwsACQl4JHUGACYDAAsACQl4JHUGACYDACcABAnYEDdgAMAAAAAA.Kongfu:BAAALgAECgYJEAAAAA==.Korravah:BAAALgAECgQJBwAAAA==.Koyuki:BAAALgAECgMJBgAAAA==.',
Kr='Kramps:BAAALgAECgQJBgAAAA==.Krandel:BAAALgAECgQJBwAAAA==.Kronan:BAAALgADCgIJAgAAAA==.',
Ku='Kuulas:BAABLgAECn8eAAILAAgJhhtDHgAtAgALAAgJhhtDHgAtAgAAAA==.',
Ky='Kyth:BAABLgAECn8zAAIZAAkJxBFgDwCCAQAZAAkJxBFgDwCCAQAAAA==.Kythlock:BAAALgADCgkJEwABLgAECgkJMwAZAMQRAA==.Kythrax:BAAALgAECgEJAQABLgAECgkJMwAZAMQRAA==.Kythtok:BAABLgAECn8cAAILAAgJpAsdUABoAQALAAgJpAsdUABoAQABLgAECgkJMwAZAMQRAA==.',
['Kê']='Kêgstand:BAAALgAECggJEQAAAA==.',
['Kø']='Køda:BAABLgAECn8oAAMBAAkJ7yLyBABCAwABAAkJ7yLyBABCAwAQAAYJ0QwwOgDdAAAAAA==.',
La='Ladyhawk:BAAALgADCgYJCQAAAA==.Lazerbird:BAAALgAECgEJAQAAAA==.',
Le='Leggy:BAAALgAECgIJAgAAAA==.Lela:BAAALgADCgEJAQAAAA==.',
Li='Life:BAAALgAECgEJAgAAAA==.Lifebloomer:BAAALgAECgQJAwABLgAFFAcJJAATAMUjAA==.Lightnup:BAAALgAECgkJDAAAAA==.Liralyn:BAAALgADCgcJDgAAAA==.Lisanndria:BAAALgADCgUJBQAAAA==.Litharaldra:BAAALgADCgYJBgAAAA==.Littlehell:BAACLgAFFH8JAAIhAAMJ1xp8DgD2AAAhAAMJ1xp8DgD2AAAuAAQKfxwAAiEACAkhG70VAGcCACEACAkhG70VAGcCAAAA.',
Lo='Lokaroki:BAAALgAECgQJBwAAAA==.Lothbrokk:BAAALgAECgUJCAAAAA==.Lothrik:BAAALgADCgIJAgAAAA==.',
Lu='Lucaafer:BAACLgAFFH8MAAIGAAMJnBNMVgD8AAAGAAMJnBNMVgD8AAAuAAQKfyUAAgYACQn9HS0zAKYCAAYACQn9HS0zAKYCAAAA.Luda:BAABLgAECn8WAAQRAAkJ8RQwEAArAQARAAQJahgwEAArAQASAAUJvRM4NQDiAAAJAAUJIhFcqgC7AAAAAA==.',
Ly='Lyssandria:BAABLgAECn8vAAIGAAkJ9wr2XACQAQAGAAkJ9wr2XACQAQAAAA==.Lyzoldas:BAABLgAECn8eAAIXAAcJvRcmXwB2AQAXAAcJvRcmXwB2AQAAAA==.',
['Lí']='Lília:BAAALgAECgEJAgAAAA==.',
['Lö']='Löwryder:BAABLgAECn8bAAIbAAcJrg1mNwAQAQAbAAcJrg1mNwAQAQAAAA==.',
Ma='Maddera:BAAALgAECgUJCAAAAA==.Madmurdock:BAABLgAECn8XAAMXAAgJKAzslQBRAQAXAAgJKAzslQBRAQAZAAMJywEDPgBGAAAAAA==.Madness:BAAALgAECgYJCwAAAA==.Maemura:BAAALgAECgUJCwAAAA==.Magîkarp:BAAALgADCgYJBwAAAA==.Mahll:BAAALgAECgIJAwAAAA==.Maiki:BAAALgAECgEJAgAAAA==.Malach:BAAALgAECgcJCQAAAA==.Malchromatus:BAABLgAECn8hAAMPAAkJ8BRGBwBLAgAPAAkJ8BRGBwBLAgAaAAQJKwd3LQCvAAAAAA==.Marcosio:BAAALgAECgIJBAAAAA==.Marsala:BAAALgAECgYJDwAAAA==.',
Mb='Mbop:BAAALgAECgQJBAAAAA==.',
Mc='Mcchud:BAAALgAECgEJAQAAAA==.',
Me='Meandragon:BAAALgADCgcJCAAAAA==.Meatyfajita:BAABLgAECn8jAAIWAAkJQCY3AADaAwAWAAkJQCY3AADaAwAAAA==.Mechabrew:BAABLgAECn8VAAIgAAYJ2w6nOwDbAAAgAAYJ2w6nOwDbAAABLgAECgkJGwAeAJUcAA==.Medousa:BAAALgAECgMJAwAAAA==.Megaera:BAAALgAECgYJDQAAAA==.Meiko:BAAALgAECgEJAQABLgAECggJHQATAIEaAA==.Meindblast:BAAALgAECggJCAAAAA==.Meladie:BAAALgAECgEJAgAAAA==.Meladrus:BAAALgADCgEJAQAAAA==.Mellene:BAAALgADCgkJFgAAAA==.Memedecay:BAABLgAECn82AAMcAAkJkCLeBwAJAwAcAAkJkCLeBwAJAwATAAEJnRkiQwA9AAAAAA==.Mememalefic:BAAALgAECgcJDAABLgAECgkJNgAcAJAiAA==.Mericck:BAAALgADCgMJAwAAAA==.Merlinthos:BAAALgAECgQJBgABLgAECgkJMAAVAMEUAA==.Metaljack:BAABLgAECn8pAAIGAAkJDyVMBgAvAwAGAAkJDyVMBgAvAwAAAA==.',
Mi='Miasma:BAAALgAECgcJDwABLgAECgMJDwANAAAAAA==.Midith:BAAALgAECgMJBAAAAA==.Mikethemage:BAAALgAECgEJAQAAAA==.Mikeyboi:BAAALgADCgEJAQAAAA==.Milanesa:BAABLgAECn8aAAIOAAkJYBMsEgDlAQAOAAkJYBMsEgDlAQAAAA==.Mingyue:BAAALgAECgYJDwABLgAECgkJNQAEAAIVAA==.Mishaweha:BAAALgAECggJDAAAAA==.Mithrandir:BAABLgAFFH8GAAIIAAMJXgtTIADUAAAIAAMJXgtTIADUAAAAAA==.Mitos:BAABLgAECn82AAIXAAgJuRM0TwCeAQAXAAgJuRM0TwCeAQAAAA==.Miyasabi:BAAALgADCgYJBgAAAA==.Mizzet:BAAALgAECgEJAQAAAA==.',
Mo='Modar:BAABLgAECn8dAAIhAAgJhhxMFABiAgAhAAgJhhxMFABiAgAAAA==.Mojopin:BAAALgAECgQJBwAAAA==.Monkas:BAAALgADCgcJCQAAAA==.Moonpaw:BAAALgAECgEJAQAAAA==.Moonrid:BAAALgAECgEJAQAAAA==.Moonshayd:BAAALgAECgcJEgAAAA==.Moreann:BAAALgADCgkJEAAAAA==.Morkepo:BAAALgADCgEJAQAAAA==.Morphëus:BAABLgAECn8dAAIGAAcJShCucQBgAQAGAAcJShCucQBgAQAAAA==.',
Mu='Muggy:BAAALgADCgIJAgABLgAFFAYJFAAcAE4jAA==.Muha:BAAALgAECgUJBQABLgAECggJEQANAAAAAA==.Murielle:BAAALgADCgUJBQAAAA==.Mushi:BAAALgADCgkJEgAAAA==.Mustardplug:BAAALgADCgEJAQAAAA==.Muzan:BAAALgAECgQJBAAAAA==.Muzzin:BAAALgADCgIJAgAAAA==.',
My='Mystiquebtb:BAAALgAECgkJDAAAAA==.',
['Må']='Måddløck:BAAALgAECgQJCgAAAA==.',
Ne='Needslotion:BAABLgAECn8VAAMaAAYJmBW+CQBKAQAaAAYJJxW+CQBKAQAEAAQJVBJfQADlAAABLgAECggJCAANAAAAAA==.Neiidra:BAAALgAECgYJDwAAAA==.Nepheleah:BAACLgAFFH8PAAIXAAUJ/xQCGgBYAQAXAAUJ/xQCGgBYAQAuAAQKfyUAAhcACQn9IVQIAPoCABcACQn9IVQIAPoCAAAA.Nesmoth:BAABLgAECn8rAAITAAcJaSQ1BgDVAgATAAcJaSQ1BgDVAgAAAA==.Ness:BAAALgAECgUJCQAAAA==.',
Ni='Niiborracho:BAABLgAECn8yAAMfAAkJaRdxDgAfAgAfAAkJaRdxDgAfAgAYAAgJNwxHLgBGAQAAAA==.Niiko:BAAALgAECgUJEAAAAA==.Niisera:BAAALgADCgQJBwAAAA==.',
No='Norntrox:BAABLgAECn8qAAMUAAgJ+xmMLADZAQAUAAgJ+xmMLADZAQAeAAEJAACxKQA9AAAAAA==.Nosåj:BAAALgADCgQJBQAAAA==.Nothannah:BAAALgAECgQJBAAAAA==.',
Ns='Nsshaman:BAAALgADCgMJAwAAAA==.',
Nu='Nuadriss:BAAALgAECgQJBAAAAA==.',
Ny='Nylaria:BAAALgADCgUJBQAAAA==.Nyxari:BAAALgAECgYJDwAAAA==.',
Ob='Obscuría:BAAALgADCgYJCgAAAA==.',
Od='Odrik:BAAALgADCgQJCAAAAA==.',
Ol='Oleana:BAAALgAECgQJBAAAAA==.Oleia:BAAALgAECgYJCQAAAA==.',
On='Onatha:BAAALgADCgkJGgAAAA==.Onaw:BAABLgAECn8VAAIlAAcJyRToDQCoAQAlAAcJyRToDQCoAQAAAA==.',
Op='Ops:BAEBLgAECn8VAAMVAAcJZA06DgAJAQAVAAYJags6DgAJAQAiAAMJmBBaNgCeAAAAAA==.',
Or='Orctism:BAAALgADCgIJAgAAAA==.',
Ow='Owlsonatotem:BAABLgAECn8hAAIhAAkJvhaDLgCwAQAhAAkJvhaDLgCwAQAAAA==.',
Ox='Oxymage:BAAALgAECgEJAgAAAA==.',
Pa='Pakno:BAAALgAECggJEgAAAA==.Paletia:BAAALgAECgYJBgAAAA==.Pamely:BAABLgAECn8UAAIXAAcJBRfvZAC3AQAXAAcJBRfvZAC3AQAAAA==.Pankler:BAAALgADCgkJCwAAAA==.',
Pe='Petethelock:BAAALgAECgYJDgAAAA==.Petethemage:BAAALgAECgIJBAAAAA==.',
Ph='Pharmit:BAABLgAECn8iAAQRAAkJ5iStAADuAgARAAkJQyStAADuAgAJAAYJ1iLUPQAVAgASAAIJ1B5tPADDAAAAAA==.Phayte:BAAALgADCgkJEAAAAA==.Photon:BAAALgADCgYJBQAAAA==.Phrock:BAAALgADCgEJAgAAAA==.',
Pl='Pletua:BAABLgAECn8eAAMiAAgJtCFaCgA7AgAiAAgJLyFaCgA7AgAVAAEJ4SMxGABqAAAAAA==.',
Po='Porazdir:BAAALgAECgUJBgAAAA==.Porcelayna:BAAALgAECgIJAwABLgAECggJKgAhADoPAA==.',
Pr='Primoris:BAAALgADCgUJBQAAAA==.',
Ps='Psion:BAAALgADCgYJBgAAAA==.',
Pu='Puds:BAAALgADCgMJAwAAAA==.',
['På']='Påimon:BAAALgADCgIJAgAAAA==.',
Qu='Quetzalcoatl:BAAALgAECggJCAAAAA==.Quintin:BAAALgAECgYJBwABLgAFFAQJCAACAH4TAA==.',
Ra='Racavis:BAAALgADCgcJCAAAAA==.Raenisa:BAEALgADCgQJBwABLgAECggJJgAFADUaAA==.Ragp:BAAALgAECgMJAwAAAA==.Rainydevil:BAAALgADCgcJDgAAAA==.Rainydevils:BAAALgADCgIJAgAAAA==.Rainymdevil:BAAALgADCgUJBQAAAA==.Rainyxdvl:BAAALgAECgEJAQAAAA==.Ramasey:BAABLgAECn8XAAMVAAcJeBYUCACOAQAVAAcJeBYUCACOAQAoAAEJwAxKGgAzAAAAAA==.Rasriann:BAAALgAECgUJBgAAAA==.Ratana:BAAALgADCgYJBQAAAA==.Rawrlordz:BAAALgAECgYJDAAAAA==.',
Re='Reaces:BAAALgADCgEJAQAAAA==.Real:BAABLgAECn8sAAIGAAkJwR4OEADNAgAGAAkJwR4OEADNAgABLgAECgYJDwANAAAAAA==.Reda:BAAALgAECgQJCgAAAA==.Reeality:BAAALgAECgYJDwAAAA==.Reelio:BAAALgAECgQJCAAAAA==.Reikio:BAAALgAECgUJBgAAAA==.Rennala:BAAALgAECgcJCAAAAA==.Repeal:BAAALgAECgQJBAAAAA==.Reptar:BAAALgADCgYJBgABLgAFFAcJHQAgAHwUAA==.Retbet:BAAALgAECgYJDwAAAA==.Revoke:BAABLgAECn8rAAIXAAkJDw9aRAC9AQAXAAkJDw9aRAC9AQAAAA==.Reyanne:BAEBLgAECn8mAAIFAAgJNRrKCwBoAgAFAAgJNRrKCwBoAgAAAA==.',
Ro='Rockfish:BAAALgAECgQJBQAAAA==.Roofio:BAAALgADCgEJAQABLgAECgkJGQAZABwiAA==.',
Ru='Rubiroo:BAAALgADCgEJAQAAAA==.Runebellwolf:BAAALgADCgcJCgAAAA==.Ruroni:BAAALgADCgUJCQAAAA==.',
Ry='Ryniel:BAABLgAECn8fAAILAAcJZhdaQACaAQALAAcJZhdaQACaAQAAAA==.Rynitty:BAAALgADCgUJBQABLgAECgcJDQANAAAAAA==.Rynthia:BAAALgADCgkJCQAAAA==.',
['Ré']='Réira:BAAALgADCgkJEQABLgAECgkJNQAEAAIVAA==.',
['Rï']='Rïptide:BAAALgAECgQJCAAAAA==.',
Sa='Sabrinalee:BAAALgADCgcJBwAAAA==.Sacremierde:BAAALgAECgUJDAAAAA==.Sagah:BAAALgAECgYJEQAAAA==.Saika:BAAALgADCgkJCQAAAA==.Saintdeamon:BAABLgAECn8hAAMBAAkJXBi+QQCaAQABAAgJJxe+QQCaAQAQAAcJSBDiKQA2AQAAAA==.Sanasta:BAABLgAECn8jAAMJAAcJyxKxWwBbAQAJAAcJgRGxWwBbAQASAAIJCRklLABEAAAAAA==.Sandspur:BAAALgAECgEJAQAAAA==.Sanielin:BAABLgAECn8gAAIgAAcJgyBAFADXAQAgAAcJgyBAFADXAQABLgAFFAEJAgANAAAAAA==.Sanielindk:BAAALgAFFAEJAgAAAA==.Saphìr:BAAALgAECgQJCwAAAA==.Sarahnox:BAAALgAECgEJAQAAAA==.Saramoon:BAABLgAECn8iAAMiAAYJWwn4KQD4AAAiAAYJWwn4KQD4AAAVAAQJhgLXFQCdAAAAAA==.Sarda:BAEALgAECgYJDQAAAA==.Sargent:BAAALgAECgcJEAAAAA==.Saryaa:BAAALgAECgcJCwAAAA==.Sashchi:BAABLgAECn8XAAIfAAgJLRKRLAAZAQAfAAgJLRKRLAAZAQAAAA==.Satheronys:BAAALgAECgQJBQAAAA==.',
Sc='Schade:BAAALgAECgQJCQAAAA==.Schrödinger:BAAALgAECgMJAwAAAA==.',
Se='Searen:BAAALgAECgQJBQAAAA==.Sehmet:BAAALgAECgMJBQAAAA==.Seiso:BAABLgAFFH8FAAICAAUJnAkSEAD7AAACAAUJnAkSEAD7AAAAAA==.Seliria:BAABLgAECn8pAAIXAAkJ+QkRXQB7AQAXAAkJ+QkRXQB7AQAAAA==.Sephaman:BAAALgAECgEJAQAAAA==.Seprogue:BAAALgADCgcJCgAAAA==.',
Sh='Shadyn:BAAALgAECgEJAQAAAA==.Shadówz:BAAALgADCgEJAQAAAA==.Shandrayn:BAAALgAECgEJAQAAAA==.Sheepstealer:BAAALgADCgQJAwAAAA==.Shiftace:BAAALgAECgQJBgAAAA==.Shiryo:BAAALgAECgMJDQAAAA==.Shockwater:BAAALgAECgUJBwAAAA==.Shotfoot:BAAALgAECgMJAwAAAA==.Shwang:BAABLgAECn8XAAILAAYJTxVKSgCKAQALAAYJTxVKSgCKAQAAAA==.',
Si='Siclock:BAAALgADCgUJBQAAAA==.Sikkerp:BAAALgADCgMJBAAAAA==.Silentio:BAABLgAECn8wAAIVAAkJwRSdBAAGAgAVAAkJwRSdBAAGAgAAAA==.Silihunt:BAAALgADCgMJAwAAAA==.Siliçå:BAAALgADCgYJCQAAAA==.Sinamun:BAABLgAECn8bAAIWAAcJWhC8QwBpAQAWAAcJWhC8QwBpAQAAAA==.Sinandtonic:BAAALgADCgQJBAAAAA==.Sinofwrath:BAABLgAECn8oAAIUAAkJviJ2BQAKAwAUAAkJviJ2BQAKAwAAAA==.Sinsidious:BAABLgAECn8dAAIcAAgJjQzGYgBqAQAcAAgJjQzGYgBqAQAAAA==.Siwin:BAACLgAFFH8ZAAIBAAYJWh1yBgASAgABAAYJWh1yBgASAgAuAAQKfyQAAwEACAm3JMsIAAIDAAEACAm3JMsIAAIDABAABQn7FtozAP0AAAAA.',
Sk='Skarlett:BAAALgAECgQJBQAAAA==.Skiller:BAAALgADCgYJDAAAAA==.Skinobi:BAAALgAECgQJBQAAAA==.Skrîbbz:BAAALgAECgEJAQAAAA==.Skysqueezer:BAAALgAECgYJCwAAAA==.',
Sl='Slapchóp:BAABLgAECn8UAAIbAAgJvRofHQCvAQAbAAgJvRofHQCvAQAAAA==.',
Sm='Smoko:BAABLgAECn8gAAIMAAgJ8h48DAArAgAMAAgJ8h48DAArAgAAAA==.',
Sn='Snorlax:BAAALgAECgIJAgABLgAECgQJBAANAAAAAA==.Snowxstorm:BAABLgAECn8oAAITAAkJOiE7BAC9AgATAAkJOiE7BAC9AgAAAA==.',
So='Sobieski:BAAALgAECgkJCQAAAA==.Solae:BAAALgADCgkJDwAAAA==.Solrond:BAAALgAECgUJCgAAAA==.Somemageguy:BAAALgAECgEJAQAAAA==.Sosimmage:BAECLgAFFH8HAAIGAAYJ6RSbGQCkAQAGAAYJ6RSbGQCkAQAuAAQKfxsAAgYACAlfH7QjAFcCAAYACAlfH7QjAFcCAAEuAAUUBQkQAAYA+R0A.Souldecay:BAABLgAECn8oAAIcAAkJ3g6qQgDDAQAcAAkJ3g6qQgDDAQAAAA==.Soultender:BAAALgADCgIJAgAAAA==.',
Sp='Spekktrum:BAAALgAECgEJAQAAAA==.',
Sq='Squidacles:BAAALgADCgEJAQAAAA==.Squirrly:BAAALgAECgEJAQAAAA==.',
St='Stainedone:BAABLgAECn8XAAIeAAgJPQ1sDQAxAQAeAAgJPQ1sDQAxAQAAAA==.Staqua:BAAALgAECgMJBQAAAA==.Stateomatter:BAAALgAECggJDwAAAA==.Stevenflowe:BAAALgADCgcJCAAAAA==.Stimpak:BAAALgAECgEJAQAAAA==.Stoneslacher:BAAALgADCgIJBAAAAA==.Streamesance:BAAALgAECgYJCAAAAA==.',
Su='Suanni:BAABLgAECn81AAQEAAkJAhXUFADzAQAEAAkJAhXUFADzAQAaAAIJVQgaGQBTAAAPAAEJoQABUAAPAAAAAA==.Summdari:BAABLgAECn8oAAIeAAkJthnOBAAgAgAeAAkJthnOBAAgAgAAAA==.Summrot:BAABLgAECn8VAAMSAAcJTxTQMgDsAAASAAUJCBXQMgDsAAAJAAQJDBLPkQDoAAAAAA==.Sunfrostt:BAAALgAECgYJEAAAAA==.Supplock:BAAALgAECgYJDwAAAA==.Suromeme:BAAALgAECgQJBAABLgAECgkJMQAlAKceAA==.',
Sw='Swizzler:BAAALgAECgQJBgAAAA==.',
Sy='Sylvalesta:BAAALgAECgMJBQAAAA==.',
Ta='Taedro:BAAALgAECgEJAQAAAA==.Taichung:BAAALgAECgUJAQAAAA==.Talyon:BAAALgAECgYJEAAAAA==.Tayge:BAAALgADCgEJAQAAAA==.',
Td='Tdogx:BAAALgAECgQJBQAAAA==.',
Te='Teafrog:BAAALgADCgcJBwAAAA==.Tekeeladin:BAAALgADCgkJCQAAAA==.Tekeelà:BAABLgAECn8ZAAMLAAYJwx4wSgB5AQALAAYJwh4wSgB5AQAMAAQJJxA3IADeAAABLgAFFAUJCQALAMMHAA==.Tenebris:BAABLgAECn8XAAIXAAYJjxiZgwBzAQAXAAYJjxiZgwBzAQAAAA==.Terrorbyte:BAAALgADCgYJBgAAAA==.Terrorhungry:BAAALgAECgUJDAAAAA==.Tessana:BAAALgADCgYJBgAAAA==.',
Th='Thalstrasza:BAABLgAECn8eAAIJAAgJtRCZSwCGAQAJAAgJtRCZSwCGAQAAAA==.Thalör:BAABLgAECn8dAAIQAAgJORfFHAAbAgAQAAgJORfFHAAbAgAAAA==.The:BAABLgAECn8kAAIKAAcJbx1/BwC0AQAKAAcJbx1/BwC0AQAAAA==.Thedevilsown:BAAALgADCgYJDgAAAA==.Thedrizzle:BAABLgAECn8hAAIGAAkJyxwvJABVAgAGAAkJyxwvJABVAgAAAA==.Thinkwizzle:BAAALgADCgYJBwAAAA==.Thunderthïgh:BAAALgAECgIJAwAAAA==.Thundrfury:BAAALgAECgUJDwAAAA==.',
Ti='Tibalt:BAABLgAECn8TAAIUAAYJUiB2VwCcAQAUAAYJUiB2VwCcAQAAAA==.Tibbles:BAAALgAECgMJBAAAAA==.Tigerlillie:BAAALgADCgIJAgAAAA==.Tipsynips:BAAALgADCgQJBAAAAA==.',
Tk='Tkla:BAAALgADCgIJAgAAAA==.',
Tl='Tlanimass:BAABLgAECn8nAAIOAAgJIxNIEgCDAQAOAAgJIxNIEgCDAQAAAA==.',
To='Tommytubstub:BAAALgAECgUJCQAAAA==.Tomstrasza:BAAALgAECgQJBgAAAA==.Tormen:BAABLgAECn8uAAImAAkJ7BLvFADhAQAmAAkJ7BLvFADhAQAAAA==.Totemforge:BAABLgAECn8eAAMhAAgJgCRGFABiAgAhAAYJtiVGFABiAgAbAAgJlhwyFwDkAQAAAA==.',
Tr='Trapdaddy:BAAALgADCgYJBgAAAA==.Traq:BAAALgADCgQJBAAAAA==.Traydranna:BAAALgADCgcJBwAAAA==.Treeko:BAAALgAECgYJDAABLgAFFAUJFAAJAMoQAA==.Treston:BAAALgAECgQJBgAAAA==.Treyna:BAAALgADCgkJEgAAAA==.',
Ts='Tsyubaki:BAAALgAECgkJEgAAAA==.',
Tw='Twistdmister:BAAALgADCgUJBAAAAA==.',
Ty='Tydes:BAAALgAECgUJCQAAAA==.Tylenya:BAAALgADCgUJCQAAAA==.Tyrian:BAAALgAECgIJAQABLgAECgMJDwANAAAAAA==.',
Ul='Uldric:BAAALgAECgcJBwAAAA==.',
Un='Undeaddude:BAAALgAECgYJBgAAAA==.Unholybrotha:BAABLgAECn8dAAITAAgJgRr6DQDeAQATAAgJgRr6DQDeAQAAAA==.Unslayable:BAAALgAECggJEgAAAA==.Unwell:BAABLgAECn8aAAQbAAcJzxF4QgA/AQAbAAcJpxB4QgA/AQAjAAQJahEIHwDgAAAhAAQJgBMHYQDfAAAAAA==.',
Ur='Urotherdaddy:BAAALgAECgMJAwABLgAECgYJEQANAAAAAA==.',
Uz='Uzzy:BAAALgAECgYJEgAAAA==.',
Va='Vaevictis:BAAALgAECgQJBwAAAA==.Valandir:BAAALgAECgYJBgAAAA==.Valenith:BAABLgAECn8aAAIMAAgJMhh5FQDAAQAMAAgJMhh5FQDAAQAAAA==.Valtora:BAAALgAECgUJCwAAAA==.Vartic:BAABLgAECn8UAAIPAAYJ9g+WFQA1AQAPAAYJ9g+WFQA1AQAAAA==.Vassago:BAAALgAECgUJCAAAAA==.',
Ve='Veliry:BAAALgADCgEJAQAAAA==.Vellarieline:BAABLgAECn8lAAIUAAcJth8hMQA2AgAUAAcJth8hMQA2AgAAAA==.Velyssara:BAAALgAECgYJEgAAAA==.Ventor:BAACLgAFFH8FAAIlAAMJih2jBgASAQAlAAMJih2jBgASAQAuAAQKfxwAAyUABwkrInIKAOMBABAABwnmIaYYAEMCACUABgkpInIKAOMBAAAA.Verbera:BAABLgAECn8kAAIBAAkJMSL9AgBzAwABAAkJMSL9AgBzAwAAAA==.',
Vi='Viduus:BAAALgAECgUJCwAAAA==.Vimah:BAAALgAECgYJCQAAAA==.Vintun:BAAALgADCgIJAgAAAA==.Virdeserti:BAABLgAECn8yAAMFAAkJpyCaAgBJAwAFAAkJpyCaAgBJAwAmAAEJAwf8XwA8AAAAAA==.Visage:BAAALgADCgkJCQAAAA==.Vixolot:BAAALgAECgIJAgAAAA==.',
Vl='Vlartank:BAAALgAECgkJBgAAAA==.',
Vm='Vmaoh:BAAALgADCggJCwAAAA==.',
Vo='Voidwithin:BAAALgAECggJEQAAAA==.',
Vu='Vulpies:BAAALgADCgYJBgAAAA==.',
Vy='Vyketh:BAAALgAECgIJAgABLgAECgYJCgANAAAAAA==.',
['Vë']='Vëil:BAAALgADCgcJBwAAAA==.',
Wa='Wandiferous:BAAALgAECgYJDwAAAA==.',
We='Webicka:BAAALgAECgQJBAAAAA==.Weezak:BAAALgAECgEJAQAAAA==.',
Wi='Wickedsmaht:BAACLgAFFH8UAAIJAAUJyhAlNwAlAQAJAAUJyhAlNwAlAQAuAAQKfyQABBIACQnkGVkWAJcBABIABwlYElkWAJcBAAkABwkhGWBoAD0BABEAAQnOGYYtAEMAAAAA.Widowghast:BAAALgADCgQJBAAAAA==.Willowísp:BAABLgAECn8vAAIgAAkJKxXVDgAYAgAgAAkJKxXVDgAYAgAAAA==.Winsfer:BAAALgAECgYJDwAAAA==.',
Wn='Wnchester:BAAALgADCgIJAgAAAA==.',
Wo='Woggers:BAAALgAECgYJDQAAAA==.',
Wr='Wrathion:BAABLgAECn8VAAMaAAcJzBpVBQDOAQAaAAcJzBpVBQDOAQAEAAIJkAxxWABdAAAAAA==.',
Wu='Wulfenstein:BAAALgADCgUJBQAAAA==.',
Wy='Wyvernman:BAAALgAECgYJCgAAAA==.Wywy:BAAALgADCgYJBgAAAA==.',
['Wí']='Wíppy:BAAALgAECgYJCwAAAA==.',
Xa='Xalthea:BAABLgAECn8qAAQUAAgJVBQJTgBaAQAUAAgJGRQJTgBaAQAeAAUJng/EFQC1AAAdAAEJ+BHZbgA2AAAAAA==.Xanda:BAACLgAFFH8TAAMVAAUJmCJNAQCdAQAVAAUJmCJNAQCdAQAiAAEJxwHvGwBMAAAuAAQKfyIAAhUACAmQH8sBAPkCABUACAmQH8sBAPkCAAAA.Xandahunt:BAAALgAECggJCAABLgAFFAUJEwAVAJgiAA==.',
Xe='Xenalah:BAAALgAECgIJAgAAAA==.',
Xi='Xikai:BAAALgADCgIJAgABLgAECgYJEgANAAAAAA==.',
Xo='Xobos:BAAALgAECgQJBQAAAA==.',
Xp='Xpddevour:BAABLgAECn83AAIUAAkJThRuLQDVAQAUAAkJThRuLQDVAQAAAA==.',
Xs='Xscapemystic:BAAALgAECgMJAwAAAA==.Xscapenature:BAAALgAECggJEgAAAA==.',
Xt='Xtena:BAAALgADCgkJCwAAAA==.Xtendron:BAACLgAFFH8PAAMXAAQJfxA6JgA4AQAXAAQJfxA6JgA4AQAWAAIJrgMEGQB6AAAuAAQKfzAAAxcACAm1IMUaAMkCABcACAm1IMUaAMkCABYABgniB9paABEBAAAA.',
Xu='Xuxo:BAAALgAECgEJAgAAAA==.',
Ya='Yaraxiu:BAAALgAECgcJCwAAAA==.',
Ye='Yegarmiester:BAABLgAECn8ZAAIGAAcJmgpFhQA5AQAGAAcJmgpFhQA5AQAAAA==.',
Yo='Yodidyoufart:BAACLgAFFH8IAAILAAMJ7hr0MQD/AAALAAMJ7hr0MQD/AAAuAAQKfy8AAwsACQkDH10YAFICAAsACQlRHl0YAFICACcACAmRFsgmAPMBAAAA.',
Za='Zaco:BAABLgAECn8vAAIDAAgJeR9dDABoAgADAAgJeR9dDABoAgAAAA==.Zakonn:BAAALgAECgQJBAAAAA==.Zarikas:BAABLgAECn8UAAIUAAYJ/RVSZgAVAQAUAAYJ/RVSZgAVAQAAAA==.Zatapatate:BAABLgAECn81AAMUAAkJfRq1GQBCAgAUAAkJehq1GQBCAgAeAAYJXhJiDwAPAQAAAA==.',
Ze='Zekken:BAAALgADCgUJBwABLgADCgYJCQANAAAAAA==.Zerality:BAABLgAECn8aAAIXAAgJWhoBPADXAQAXAAgJWhoBPADXAQAAAA==.',
Zh='Zhachy:BAACLgAFFH8MAAMaAAQJThy2AQBhAQAaAAQJlhm2AQBhAQAEAAMJNRplKADmAAAuAAQKfzUABAQACQnfIhsPAIUCAAQACAlkIRsPAIUCABoACAn+Ii4KADwCAA8AAwnIFOwdAMwAAAAA.',
Zi='Ziggie:BAABLgAECn83AAIUAAkJvyV5AQBhAwAUAAkJvyV5AQBhAwAAAA==.Zinovia:BAACLgAFFH8IAAQfAAMJBB/7DQAZAQAfAAMJBB/7DQAZAQAYAAEJUw0/OAA2AAAgAAEJqQO8SwAzAAAuAAQKfxwABB8ACQmfIMARAGoCAB8ACQmfIMARAGoCACAABgmhFxkxAJABABgABQnuGI0uAEUBAAAA.Ziwei:BAAALgAECgUJCQABLgAECgkJNQAEAAIVAA==.',
Zo='Zombieboy:BAAALgAECgcJBgAAAA==.Zookee:BAABLgAECn8pAAIYAAkJRRpmCwCNAgAYAAkJRRpmCwCNAgAAAA==.Zopilote:BAAALgAECgEJAQAAAA==.',
['Ðe']='Ðeathguise:BAAALgADCgMJAwAAAA==.',
['Ön']='Önlish:BAAALgAECgEJAQABLgAECgcJDAANAAAAAA==.Önlîsh:BAAALgADCgMJAwABLgAECgcJDAANAAAAAA==.',
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
