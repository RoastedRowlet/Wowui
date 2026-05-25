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

local lookup = {'Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Arms','Priest-Holy','Paladin-Retribution','Paladin-Holy','DemonHunter-Devourer','Druid-Restoration','Druid-Guardian','Mage-Frost','Priest-Shadow','Hunter-BeastMastery','Unknown-Unknown','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','DemonHunter-Havoc','DeathKnight-Unholy','Monk-Brewmaster','Druid-Balance','Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','Hunter-Marksmanship','Mage-Arcane','DeathKnight-Blood','Rogue-Assassination','Priest-Discipline','Warlock-Affliction','DeathKnight-Frost','Druid-Feral','Monk-Mistweaver','Hunter-Survival','Rogue-Subtlety',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=46,date='2026-05-24',data={Ad='Addiction:BAAALgADCgYJAQAAAA==.',
Ah='Ahmet:BAAALgAECgkJEwABLgAECgkJPgABAI0dAA==.',
Ai='Aiax:BAACLgAFFH8IAAICAAMJRAJsHQCXAAACAAMJRAJsHQCXAAAuAAQKfxcABAMACAlODDQgACwBAAQABgmnDb0xADoBAAMABglkCjQgACwBAAIAAglJB0VGAEAAAAAA.',
Al='Aliancia:BAABLgAECn8wAAMFAAgJXhSWEwCPAQAFAAgJXhSWEwCPAQAGAAMJ3Aa1VABOAAAAAA==.Almur:BAAALgAECgYJCQAAAA==.Alyda:BAAALgADCggJFAAAAA==.Alydin:BAAALgADCgUJBQAAAA==.',
Am='Amalthea:BAAALgAECgEJAQAAAA==.Amet:BAABLgAECn8+AAIBAAkJjR0pBACcAgABAAkJjR0pBACcAgAAAA==.',
An='Anakinn:BAAALgAECgUJBQAAAA==.Annailuj:BAAALgADCgIJAgAAAA==.Annora:BAABLgAECn8wAAIHAAkJBxuzDwBJAgAHAAkJBxuzDwBJAgAAAA==.Antherina:BAAALgADCgQJBwAAAA==.Antonious:BAAALgADCgMJAwAAAA==.Antonlavay:BAAALgAECgQJBAAAAA==.',
Ap='Aphyra:BAAALgADCgUJBQAAAA==.Apollyon:BAACLgAFFH8FAAIIAAQJ/CDWFACEAQAIAAQJ/CDWFACEAQAuAAQKfycAAwgACQnEIVEMAOkCAAgACQnEIVEMAOkCAAkAAgkqFax+AH8AAAAA.',
Ar='Arlechino:BAACLgAFFH8IAAIKAAQJ9ghgQwD0AAAKAAQJ9ghgQwD0AAAuAAQKfxwAAgoACAkXF1lAAPMBAAoACAkXF1lAAPMBAAAA.Arywyn:BAABLgAECn8ZAAILAAcJNwuTXQAAAQALAAcJNwuTXQAAAQAAAA==.',
As='Assclapiuss:BAABLgAECn83AAMIAAkJiyUbAwBbAwAIAAkJiyUbAwBbAwAJAAEJTwe2hQApAAAAAA==.Asterchades:BAABLgAECn9CAAIMAAkJSx44BACuAgAMAAkJSx44BACuAgAAAA==.Astlin:BAAALgAECgEJAQAAAA==.Astraeastar:BAAALgADCgUJBQAAAA==.',
At='Athennah:BAAALgAECgcJBwABLgAECggJHQANAAwdAA==.Atrei:BAAALgADCgIJAgAAAA==.Attikus:BAABLgAECn8/AAINAAkJ1gOHiwBHAQANAAkJ1gOHiwBHAQAAAA==.Atuan:BAABLgAECn8ZAAIOAAcJfxIuKQBgAQAOAAcJfxIuKQBgAQAAAA==.',
Au='Auralass:BAABLgAECn8bAAIPAAgJXRbFNgDZAQAPAAgJXRbFNgDZAQAAAA==.Aurene:BAAALgAECgkJMAAAAQ==.Autym:BAAALgADCgkJCQAAAA==.',
Av='Avaric:BAAALgAECgEJAQABLgAECgcJDQAQAAAAAA==.Avatard:BAAALgAECgIJAgABLgAFFAQJCQANAJ0DAA==.',
Ax='Axem:BAABLgAECn8pAAIRAAkJmB35CQCkAgARAAkJmB35CQCkAgAAAA==.',
Az='Azlanii:BAAALgADCggJCgAAAA==.Azulathan:BAABLgAECn8bAAMSAAgJ3BYwCADOAQASAAgJ3BYwCADOAQAKAAcJwwq9jgAEAQABLgAECggJNAATAP4TAA==.',
Ba='Bamseyn:BAAALgADCgYJCwAAAA==.Bamsheyn:BAAALgADCgkJCQAAAA==.Baraxor:BAABLgAECn80AAMTAAgJ/hMEOACiAQATAAgJ/hMEOACiAQAUAAgJrw9vNAA+AQAAAA==.Barrelaged:BAAALgAECgMJAwAAAA==.',
Be='Beerguy:BAAALgAECgYJDwAAAA==.Behemothe:BAABLgAECn86AAIVAAkJhSEHAgDrAgAVAAkJhSEHAgDrAgAAAA==.Berníesandrs:BAABLgAECn8sAAINAAgJeQ+FdgBxAQANAAgJeQ+FdgBxAQAAAA==.Beryllos:BAAALgAECgMJCAAAAA==.Bevela:BAAALgADCgIJAgAAAA==.',
Bi='Biddies:BAAALgAECggJDgAAAA==.Bigdmg:BAAALgAFFAIJAwAAAA==.Biggusdiscus:BAAALgAECgMJAwAAAA==.Bigimpin:BAAALgADCgcJBwAAAA==.Bisky:BAAALgAECgMJAwABLgAECgkJHwAWANYaAA==.',
Bj='Bjôrn:BAAALgAECgcJDQAAAA==.',
Bl='Bledana:BAAALgAECgUJBgAAAA==.Bleué:BAAALgADCgEJAQABLgAECgkJMwALAPEaAA==.Bloodmourne:BAABLgAECn8yAAIXAAkJmSWXAwBXAwAXAAkJmSWXAwBXAwAAAA==.Bloodytoutii:BAAALgAECgYJCgAAAA==.',
Bo='Borthyr:BAABLgAECn8pAAMEAAkJfh2RCQCmAgAEAAkJYByRCQCmAgADAAYJ0RyqDgDwAQAAAA==.Bortman:BAAALgAECgQJBAABLgAECgkJKQAEAH4dAA==.Bowowner:BAABLgAECn8hAAIPAAgJxh6BMADxAQAPAAgJxh6BMADxAQAAAA==.',
Br='Branchmanagr:BAABLgAECn8iAAIMAAkJ6RFjDwC2AQAMAAkJ6RFjDwC2AQAAAA==.Brewlee:BAAALgAECgkJEQAAAA==.Bricter:BAAALgADCgkJCQABLgAECgkJNgANAFkVAA==.Brokenkrayon:BAAALgAECgQJBgAAAA==.Brokkr:BAAALgADCgQJBwAAAA==.Bryce:BAAALgAECgEJAQAAAA==.',
Bu='Bullséye:BAAALgAECgEJAQAAAA==.Busta:BAABLgAECn8fAAINAAkJZwXJlwAxAQANAAkJZwXJlwAxAQAAAA==.',
Bw='Bwicked:BAABLgAECn8dAAINAAgJoxUlUADRAQANAAgJoxUlUADRAQAAAA==.',
['Bé']='Béck:BAAALgADCgEJAQAAAA==.',
['Bü']='Büg:BAAALgAECgcJDwAAAA==.',
Ca='Caedars:BAAALgADCgEJAQAAAA==.Calzone:BAAALgAECgQJBgAAAA==.Cantpurge:BAAALgADCgIJAgABLgAECgcJFQAOAAcIAA==.Carebears:BAAALgAECgQJBQAAAA==.',
Ce='Celonge:BAAALgAECgEJAQABLgAECgkJMAAJAOsYAA==.',
Ch='Chamelean:BAAALgAECgYJDQABLgAECgkJHgAKAAwVAA==.Charmcaster:BAAALgADCgQJBQAAAA==.Chimpnzthat:BAABLgAECn8jAAIYAAgJXRJIIQCBAQAYAAgJXRJIIQCBAQAAAA==.Chookicookie:BAABLgAECn8+AAMUAAkJ9h7TBwDBAgAUAAkJ9h7TBwDBAgATAAgJPiIyFgBkAgAAAA==.Chrome:BAABLgAECn9CAAMZAAkJ3CAuBAAEAwAZAAkJ3CAuBAAEAwALAAgJyB1+HgBLAgAAAA==.Chuckarita:BAABLgAECn8gAAIZAAkJnQo6KgBUAQAZAAkJnQo6KgBUAQAAAA==.',
Ci='Cindyy:BAABLgAECn8iAAIaAAgJiyEGCQCRAgAaAAgJiyEGCQCRAgABLgAECgkJIwAPAA4eAA==.Civaelia:BAAALgADCgMJAwAAAA==.',
Cl='Clutterbear:BAAALgADCgIJAgAAAA==.',
Co='Coedwig:BAAALgADCgYJBgAAAA==.Consfiracy:BAAALgAFFAEJAQAAAA==.Coresh:BAAALgAECgQJBAAAAA==.Cornpuff:BAABLgAECn8XAAMbAAcJECX8BwCkAQAbAAUJ+CT8BwCkAQAcAAMJpCTsdAA8AQAAAA==.Cortiz:BAABLgAECn9CAAIPAAkJaRK2MwDkAQAPAAkJaRK2MwDkAQAAAA==.',
Cr='Crankdog:BAABLgAECn8rAAMPAAkJ1iQjAwBIAwAPAAkJ1iQjAwBIAwAdAAYJ8g9oSgApAQAAAA==.Creedd:BAABLgAECn8vAAILAAgJGiAvEQCoAgALAAgJGiAvEQCoAgABLgAECgkJEQAQAAAAAA==.Crialta:BAAALgADCgcJFAAAAA==.',
Cu='Cupsandcakes:BAABLgAECn8WAAIeAAcJ3Qe1BwAAAQAeAAcJ3Qe1BwAAAQAAAA==.',
Cy='Cynaidia:BAAALgAECgQJBwAAAA==.',
Da='Dacarry:BAAALgAECgIJAgAAAA==.Damessiah:BAABLgAECn8pAAMHAAgJGRSrGQDXAQAHAAgJGRSrGQDXAQAOAAEJ8AE+gAAYAAAAAA==.Dark:BAABLgAECn89AAIcAAkJ/x/sDADRAgAcAAkJ/x/sDADRAgAAAA==.Darkphyre:BAABLgAECn8YAAIIAAcJzgxYkgAvAQAIAAcJzgxYkgAvAQAAAA==.Darkstormn:BAAALgADCggJCAAAAA==.Darthtree:BAAALgADCgEJAQAAAA==.Dawling:BAAALgAECggJCQAAAA==.',
De='Deadmandan:BAABLgAECn8vAAMcAAkJHSXCBQBgAwAcAAkJHSXCBQBgAwAbAAYJISSxBwBMAgAAAA==.Deathomen:BAAALgADCgcJBwAAAA==.Deathtike:BAABLgAECn88AAIfAAkJyiTuAABQAwAfAAkJyiTuAABQAwABLgAECgkJPwASAFYlAA==.Decius:BAABLgAECn8YAAIgAAcJkAfzDgAYAQAgAAcJkAfzDgAYAQAAAA==.Dedsexxy:BAAALgADCgQJBAAAAA==.Deltairlines:BAABLgAFFH8IAAMEAAUJPREYJQALAQAEAAUJPREYJQALAQACAAMJ9gPuHACfAAABLgAFFAUJCQATAAYHAA==.Deltayaya:BAABLgAFFH8JAAITAAUJBgcjIQAuAQATAAUJBgcjIQAuAQAAAA==.Demagorgin:BAABLgAECn84AAIIAAkJnhzRGQCMAgAIAAkJnhzRGQCMAgAAAA==.Demcheekz:BAAALgAECgIJAgAAAA==.Demiurge:BAAALgAECgUJBQAAAA==.Demondred:BAABLgAECn8UAAMhAAcJHwpUNwAIAQAhAAYJ6AhUNwAIAQAHAAQJpQlVRgCnAAAAAA==.Demonplug:BAAALgADCgEJAQAAAA==.Demonrae:BAAALgAECgIJAgAAAA==.Deqlyn:BAABLgAECn8wAAIIAAkJ7B5gDwDSAgAIAAkJ7B5gDwDSAgAAAA==.Desmus:BAABLgAECn8jAAIZAAgJCRZPHAC8AQAZAAgJCRZPHAC8AQAAAA==.Deterno:BAAALgADCgUJBQAAAA==.Devige:BAAALgADCgMJBAABLgAFFAQJDwAcAO0gAA==.Devilmaycry:BAAALgADCgEJAQAAAA==.Deáthreaver:BAABLgAECn8iAAIIAAkJpw33VACvAQAIAAkJpw33VACvAQAAAA==.',
Di='Diglett:BAAALgADCgYJAQAAAA==.Dimsum:BAAALgAECgUJBgAAAA==.Diqtator:BAAALgADCgcJBwAAAA==.Dismal:BAABLgAECn8eAAIJAAkJJhLYHQDwAQAJAAkJJhLYHQDwAQAAAA==.Ditar:BAAALgAECgEJAgABLgAECgYJCgAQAAAAAA==.',
Dk='Dk:BAAALgADCgIJAgABLgAFFAMJCQAPABkkAA==.',
Do='Domwarlock:BAABLgAFFH8HAAMiAAMJjQxUGgBKAAAcAAIJ+AusiQCLAAAiAAEJtQ1UGgBKAAAAAA==.Doogang:BAAALgADCgEJAQAAAA==.Doomdooms:BAAALgADCgEJAQAAAA==.Dots:BAAALgADCggJDgAAAA==.',
Dr='Dradin:BAAALgADCgMJAwAAAA==.Dragondznutz:BAAALgAECgYJDAABLgAECgkJNwAIAIslAA==.Dronin:BAABLgAECn8jAAMdAAgJCRgwDQBlAQAdAAcJZBYwDQBlAQAPAAMJ3hqmtgCdAAAAAA==.Drpatan:BAABLgAECn8fAAIWAAcJrgcoMQDIAAAWAAcJrgcoMQDIAAAAAA==.Druni:BAABLgAECn8ZAAIBAAcJYgdFJADFAAABAAcJYgdFJADFAAAAAA==.Dryan:BAAALgADCgEJAQAAAA==.',
Ec='Echowalker:BAABLgAECn8ZAAIWAAgJnRhTEQDjAQAWAAgJnRhTEQDjAQAAAA==.',
Ee='Eecho:BAAALgADCgEJAQAAAA==.',
Eh='Ehdawg:BAAALgAECgEJAQAAAA==.',
Ei='Eisenthorne:BAAALgADCgEJAgAAAA==.',
El='Eldruida:BAAALgADCgYJDAAAAA==.Elemann:BAAALgAECgQJBAAAAA==.Elguezo:BAAALgAECgYJDwAAAA==.Elysyn:BAAALgADCgMJAwAAAA==.',
Em='Emaelia:BAAALgAECgQJBAAAAA==.Emmerick:BAAALgAECgMJAwAAAA==.Emokillaz:BAABLgAECn8WAAIWAAcJ2hitIwCgAQAWAAcJ2hitIwCgAQAAAA==.',
Ep='Epictaxes:BAAALgAECgYJBgAAAA==.Epimetheuz:BAAALgADCgYJAwABLgAECgcJBwAQAAAAAA==.Epsi:BAAALgADCgQJBAAAAA==.Epsilón:BAABLgAECn8VAAIOAAcJBwiAPwDrAAAOAAcJBwiAPwDrAAAAAA==.',
Et='Eternalpeace:BAAALgAECgEJAgAAAA==.',
Ev='Evelana:BAAALgADCgQJBwAAAA==.',
Ex='Exaduss:BAABLgAECn8VAAMbAAgJUyH+CAAxAgAbAAgJUyH+CAAxAgAcAAQJHB6XdQA7AQAAAA==.',
Ez='Ezora:BAAALgAECgcJDAAAAA==.',
Fa='Famulimus:BAAALgAECgcJCgABLgAECgkJFQALAEsXAA==.Fastrolling:BAAALgADCgQJCgAAAA==.Faxon:BAABLgAECn8iAAIPAAkJ8xfOIgAvAgAPAAkJ8xfOIgAvAgAAAA==.Faylan:BAABLgAECn8VAAIPAAYJ/A3egQAPAQAPAAYJ/A3egQAPAQAAAA==.',
Fe='Feronnia:BAAALgAECgMJAwAAAA==.',
Fi='Fibot:BAABLgAECn82AAIVAAkJ/xxcBACKAgAVAAkJ/xxcBACKAgAAAA==.Fingon:BAAALgAECgcJEgAAAA==.',
Fl='Flogor:BAAALgAECgcJBgABLgAECgkJFwANAAATAA==.Florasol:BAAALgADCgIJAgAAAA==.',
Fo='Foxling:BAEALgAECgQJBgAAAA==.',
Fr='Fraeyah:BAAALgAECgcJBwAAAA==.Frahaad:BAAALgADCgQJBAAAAA==.Freebunz:BAACLgAFFH8KAAINAAQJKA1fTgAvAQANAAQJKA1fTgAvAQAuAAQKfxYAAg0ACQkaF2ZUADsCAA0ACQkaF2ZUADsCAAAA.',
Fu='Fulgora:BAAALgAECgcJDQAAAA==.Fullmoon:BAAALgAECgcJBwAAAA==.Furicor:BAAALgADCgEJAQAAAA==.',
Ga='Gahydra:BAAALgADCgkJEwAAAA==.Galvanize:BAACLgAFFH8RAAINAAQJDQu9UwAjAQANAAQJDQu9UwAjAQAuAAQKfz4AAg0ACQnGGzUjAHYCAA0ACQnGGzUjAHYCAAAA.Gasaraki:BAAALgAECgEJAgAAAA==.Gastdhunter:BAAALgAECgEJAQAAAA==.Gastrophos:BAAALgAECgEJAQAAAA==.',
Gh='Ghomertin:BAAALgADCggJCgAAAA==.',
Gi='Gimtar:BAAALgAECgYJCgAAAA==.Ginjockey:BAAALgADCgUJBQABLgAECgcJFQAOAAcIAA==.Gipsydanger:BAACLgAFFH8FAAIhAAIJzxj/KwCeAAAhAAIJzxj/KwCeAAAuAAQKfz8AAiEACQndHDEJALsCACEACQndHDEJALsCAAAA.Girllygirl:BAAALgAECgYJDAAAAA==.Givr:BAAALgADCgEJAQAAAA==.',
Gl='Gladiatrix:BAAALgAECgQJCAAAAA==.Glaurang:BAAALgAECgQJCwAAAA==.Glofor:BAAALgAECgcJDwABLgAECgkJFwANAAATAA==.',
Gn='Gnarp:BAAALgADCgEJAQABLgAECggJGAATAMcWAA==.Gnomeregrets:BAAALgAECgUJBQABLgAECgYJDQAQAAAAAA==.Gnomestone:BAAALgAECgcJDAAAAA==.',
Go='Goldencorpse:BAAALgAECgUJBQAAAA==.Goldenspoon:BAAALgADCgEJAQABLgAFFAIJBQAXACIeAA==.Gorlokk:BAEALgADCgMJAwABLgAECgUJBQAQAAAAAA==.',
Gr='Grakonys:BAABLgAECn8zAAMEAAkJThGOHADUAQAEAAkJThGOHADUAQADAAcJ4Qc7HQBFAQAAAA==.Granger:BAAALgAECgIJAgABLgAECgIJBAAQAAAAAA==.Greed:BAABLgAECn80AAIaAAkJHRtxCgB5AgAaAAkJHRtxCgB5AgAAAA==.Greensun:BAAALgADCgEJAQAAAA==.Grendol:BAAALgAECgMJAwAAAA==.Grimmbot:BAAALgAECgMJBQAAAA==.Grimmvelt:BAAALgAECgQJBAAAAA==.Grounch:BAAALgADCgUJBQAAAA==.Grunnck:BAAALgADCgkJJwAAAA==.',
Gu='Guayusa:BAAALgAECggJEwAAAA==.Gunned:BAAALgADCgEJAQAAAA==.',
Gw='Gwendolin:BAAALgAECgUJBQAAAA==.Gwenfrewi:BAAALgADCgEJAQABLgADCgEJAQAQAAAAAA==.',
Ha='Hacheron:BAAALgADCgIJAgABLgAFFAQJCAAfADkQAA==.Hallows:BAAALgAECgQJBQAAAA==.Harnix:BAABLgAECn8dAAIIAAcJGA2okAAyAQAIAAcJGA2okAAyAQAAAA==.Harron:BAAALgAECgUJBQAAAA==.Hawtbooty:BAABLgAECn8uAAIHAAkJDRwzFAASAgAHAAkJDRwzFAASAgAAAA==.',
He='Heartsbane:BAAALgAECgEJAQAAAA==.Helixrage:BAABLgAECn8XAAIFAAkJ/QWJHgAYAQAFAAkJ/QWJHgAYAQAAAA==.Hellreines:BAABLgAECn8fAAIjAAcJkiJPBQAoAgAjAAcJkiJPBQAoAgAAAA==.Herpderplol:BAABLgAECn8cAAIkAAkJDBGJDAC+AQAkAAkJDBGJDAC+AQAAAA==.',
Hi='Hildi:BAABLgAECn8jAAMlAAgJSgIQZACRAAAlAAgJSgIQZACRAAAaAAEJyAEnjAAfAAAAAA==.Him:BAACLgAFFH8HAAIRAAMJ0RjSJADuAAARAAMJ0RjSJADuAAAuAAQKfyoAAhEACQmcI30DABoDABEACQmcI30DABoDAAAA.',
Ho='Holy:BAACLgAFFH8FAAIhAAIJDREALwCNAAAhAAIJDREALwCNAAAuAAQKfzkAAyEACQk6INgDAEIDACEACQk6INgDAEIDAAcAAQmDHO5ZAEsAAAAA.Holyscales:BAAALgAECgEJAQAAAA==.Hoots:BAAALgAECgQJBQAAAA==.',
Hu='Hucklebury:BAAALgADCgYJDQAAAA==.Hulkcrush:BAAALgADCgcJGAAAAA==.Humânity:BAAALgADCgYJBgAAAA==.Hurcules:BAAALgAECgUJBQAAAA==.',
['Hø']='Høåx:BAAALgAECgMJAwABLgAECgQJBAAQAAAAAA==.',
Il='Illbloodarch:BAABLgAECn8vAAIGAAkJWw1hFACXAQAGAAkJWw1hFACXAQAAAA==.Illvicious:BAAALgAECgMJBgAAAA==.',
In='Incredibread:BAAALgAECgYJCgAAAA==.Indub:BAAALgAECgcJCwAAAA==.',
Ir='Ironfistmogu:BAAALgADCgkJCQAAAA==.',
Is='Ishura:BAABLgAECn8dAAIJAAgJTwrUNABYAQAJAAgJTwrUNABYAQAAAA==.',
It='Itslevi:BAAALgAECgcJEgAAAA==.',
Iv='Ivvy:BAABLgAECn8WAAIZAAcJ1gfpPQDpAAAZAAcJ1gfpPQDpAAAAAA==.',
Iz='Izanami:BAABLgAECn8jAAIWAAcJhBzmDwD3AQAWAAcJhBzmDwD3AQAAAA==.',
Ja='Jadinkalage:BAAALgAECgQJBAAAAA==.Jaewreth:BAAALgAECgIJAgAAAA==.Janntro:BAABLgAECn8fAAMWAAkJ1ho7CwBCAgAWAAkJmho7CwBCAgASAAIJ4hj+GwCVAAAAAA==.Jantra:BAAALgAECgEJAgABLgAECgkJHwAWANYaAA==.Jantro:BAABLgAECn8bAAIMAAkJqh7FBACaAgAMAAkJqh7FBACaAgABLgAECgkJHwAWANYaAA==.Janttro:BAAALgAECgIJBAABLgAECgkJHwAWANYaAA==.Jaquavious:BAAALgADCgcJBwAAAA==.',
Je='Jeebz:BAABLgAECn8oAAMTAAkJshPNMADFAQATAAkJshPNMADFAQAUAAMJxQqUbACRAAAAAA==.Jelmarr:BAAALgAECgcJDwAAAA==.Jemmâ:BAAALgAECggJEwAAAA==.Jerauld:BAABLgAECn8iAAIkAAgJIg94EQBuAQAkAAgJIg94EQBuAQAAAA==.Jezrra:BAAALgAECggJDwAAAA==.',
Jh='Jhuloot:BAAALgAECgEJAQAAAA==.',
Ji='Jiddles:BAAALgADCgMJAwABLgAECgkJHgATAIEdAA==.',
Jo='Johnnyzyns:BAABLgAECn8yAAMXAAkJOB13FgChAgAXAAkJOB13FgChAgAfAAEJthh2SgA+AAAAAA==.Jokhasta:BAABLgAECn8ZAAIVAAgJvBY/CwAYAgAVAAgJvBY/CwAYAgAAAA==.Joshc:BAABLgAECn8yAAIMAAkJHg3gGQBDAQAMAAkJHg3gGQBDAQAAAA==.',
Jp='Jpmeister:BAAALgADCgkJDQAAAA==.',
Ju='Judgejudee:BAAALgADCgcJFgAAAA==.Judgédred:BAAALgAECgcJCgAAAA==.',
['Já']='Ják:BAABLgAECn8bAAQBAAgJzBMPGwA2AQABAAcJJhEPGwA2AQAJAAMJvwu6bwBSAAAIAAEJpwPJfwEmAAAAAA==.',
Ka='Kaaris:BAABLgAECn8bAAIbAAkJsAv1CgBmAQAbAAkJsAv1CgBmAQAAAA==.Kaetora:BAAALgADCgkJCQAAAA==.Kaiarie:BAABLgAECn8bAAIiAAgJ4gcdEAAsAQAiAAgJ4gcdEAAsAQAAAA==.Kainraziel:BAABLgAECn8eAAIKAAkJDBUCMwDcAQAKAAkJDBUCMwDcAQAAAA==.Kairos:BAABLgAECn8+AAINAAkJ2w7wSwDeAQANAAkJ2w7wSwDeAQAAAA==.Kalasta:BAAALgADCgIJAgAAAA==.Kanzak:BAAALgADCgcJCgAAAA==.Karem:BAAALgAECgEJAQAAAA==.Karkea:BAAALgAECgEJBAAAAA==.Kayper:BAAALgAECgcJAgAAAA==.Kayyos:BAAALgAECgkJCQAAAA==.',
Ke='Kebin:BAABLgAECn8xAAIFAAkJvhdRCwAXAgAFAAkJvhdRCwAXAgAAAA==.Kekkoken:BAAALgAECgEJAQAAAA==.Kelfhammer:BAAALgADCgQJBAAAAA==.Kenkenif:BAAALgAECgUJCQAAAA==.',
Kh='Khlorox:BAAALgADCgYJBgAAAA==.Khronin:BAAALgADCgIJAgAAAA==.',
Ki='Killmonger:BAAALgAECgYJCwAAAA==.Kimsambo:BAAALgAECgQJBAAAAA==.',
Kl='Klöwÿ:BAAALgAECgEJAQAAAA==.',
Ko='Korax:BAAALgAECgUJBQAAAA==.Korgia:BAAALgAECgQJBAAAAA==.Kortharion:BAABLgAECn8yAAICAAkJTiP6AACVAwACAAkJTiP6AACVAwAAAA==.Korzillian:BAAALgAECgEJAQAAAA==.Kos:BAABLgAECn8kAAIOAAkJsSGSBAD4AgAOAAkJsSGSBAD4AgAAAA==.',
Kr='Kreyali:BAAALgAECgIJAgAAAA==.Krixis:BAAALgADCgEJAgAAAA==.',
Ku='Kujiera:BAAALgAECgcJEwAAAA==.Kuntar:BAAALgAECgcJCwAAAA==.Kurgan:BAAALgADCggJCAAAAA==.Kurkoh:BAAALgAECgIJBAAAAA==.Kurrent:BAABLgAECn8eAAITAAkJgR2DEgCQAgATAAkJgR2DEgCQAgAAAA==.',
['Kÿ']='Kÿtten:BAABLgAECn8kAAIBAAkJwwoeFQBSAQABAAkJwwoeFQBSAQAAAA==.',
La='Lad:BAABLgAECn8XAAMXAAkJch/dDADpAgAXAAkJch/dDADpAgAjAAEJHgqjFwAxAAAAAA==.Laiyth:BAABLgAECn8bAAIcAAkJfxIBMgD7AQAcAAkJfxIBMgD7AQAAAA==.Lanfearz:BAAALgADCgEJAQAAAA==.Larryfish:BAABLgAECn8iAAMXAAkJQx+IHAB8AgAXAAkJjB6IHAB8AgAjAAcJLx3+BQARAgAAAA==.Laslock:BAAALgADCgEJAQAAAA==.Lavahitman:BAAALgAECgMJBgAAAA==.Lavos:BAABLgAECn8wAAIbAAkJ1A4ZCQCLAQAbAAkJ1A4ZCQCLAQAAAA==.',
Le='Levitikus:BAAALgAECgIJBgAAAA==.Levìtikus:BAAALgAECgEJAgAAAA==.',
Li='Lideysse:BAAALgADCgUJBQAAAA==.Lighteyes:BAAALgADCgEJAQAAAA==.Lildragon:BAAALgAECgYJBgAAAA==.Lisster:BAABLgAECn8zAAMPAAkJzyBwCgDgAgAPAAkJzyBwCgDgAgAdAAEJkAG2mAAeAAAAAA==.Littledoty:BAAALgAECgEJAQAAAA==.Liyra:BAABLgAECn8dAAMJAAkJNhuwIAAWAgAJAAkJNhuwIAAWAgABAAEJBBULQQA5AAAAAA==.Lizcandor:BAAALgAECgMJDQAAAA==.',
Lo='Loafe:BAACLgAFFH8HAAIIAAQJIgngPQAQAQAIAAQJIgngPQAQAQAuAAQKfykAAggACAk6DyNlALYBAAgACAk6DyNlALYBAAAA.Lokni:BAAALgAECgYJEQAAAA==.Loriann:BAAALgAECgEJAQAAAA==.Loumin:BAAALgADCgkJCQAAAA==.',
Lu='Ludacritz:BAAALgAECggJDgAAAA==.Lunaignis:BAAALgADCgYJBgAAAA==.Lunasera:BAAALgADCgcJBwAAAA==.Luthais:BAABLgAECn8ZAAIBAAcJCQ5NHQAAAQABAAcJCQ5NHQAAAQAAAA==.Luxury:BAABLgAECn8sAAIFAAkJrQKPIwDtAAAFAAkJrQKPIwDtAAAAAA==.',
Ly='Lykanthropos:BAAALgADCgcJBwAAAA==.',
Ma='Mahroq:BAABLgAECn8lAAMHAAgJwhk2HgDtAQAHAAgJnxk2HgDtAQAhAAUJgwe4RwCqAAAAAA==.Mako:BAACLgAFFH8MAAICAAQJ8gwyFgACAQACAAQJ8gwyFgACAQAuAAQKfx0AAgIACAn6IP8DAN4CAAIACAn6IP8DAN4CAAAA.Malarkeclark:BAAALgADCgkJCQAAAA==.Malevian:BAABLgAECn8nAAMDAAgJDww0DAAxAQADAAgJygg0DAAxAQAEAAcJtgq8NQAjAQAAAA==.Malfuridan:BAAALgAECgMJAgAAAA==.Malocki:BAAALgADCgQJCgAAAA==.Mandas:BAAALgAECgEJAQAAAA==.Maples:BAABLgAECn8nAAMlAAkJXwrgMgBfAQAlAAkJXwrgMgBfAQAaAAMJ3gGtngAVAAAAAA==.Mariasha:BAAALgAECgUJDgAAAA==.Marichika:BAAALgADCgcJEQAAAA==.Maryjaine:BAAALgAECgQJBAAAAA==.Mattdeamon:BAAALgADCgUJBwABLgAFFAQJEQANAA0LAA==.Mazzikin:BAABLgAECn8nAAIKAAkJDB+ODQC/AgAKAAkJDB+ODQC/AgAAAA==.',
Mc='Mcdodgy:BAAALgADCgEJAQAAAA==.',
Me='Megaterium:BAABLgAECn8sAAMHAAgJdhpDEgAoAgAHAAgJdhpDEgAoAgAOAAYJnQqrUACeAAAAAA==.Menethil:BAABLgAECn8eAAIJAAgJkiN2CgDCAgAJAAgJkiN2CgDCAgAAAA==.Metheuz:BAAALgAECgcJBwAAAA==.Mexican:BAABLgAECn8yAAINAAkJPxMIPgAJAgANAAkJPxMIPgAJAgAAAA==.',
Mi='Midnightlock:BAAALgAECgYJDQAAAA==.Midnyght:BAAALgAECgMJCAAAAA==.Mishgrail:BAABLgAECn8wAAIYAAkJyCDNAwD3AgAYAAkJyCDNAwD3AgAAAA==.Misosoup:BAAALgAECgUJBQABLgADCgEJAQAQAAAAAA==.Missmisery:BAABLgAECn8dAAIPAAkJ1g6eOADSAQAPAAkJ1g6eOADSAQAAAA==.Mithdraug:BAABLgAECn8YAAMZAAcJthHXOAABAQAZAAYJZhDXOAABAQALAAQJdwZ1qwBJAAAAAA==.Mitzi:BAACLgAFFH8YAAMXAAcJ0RbfFgC8AQAXAAYJ0RbfFgC8AQAfAAEJAAAISwAAAAAuAAQKfyQAAhcACQlwI14aAN8CABcACQlwI14aAN8CAAAA.',
Mo='Modrem:BAAALgADCgkJEgAAAA==.Mokhan:BAAALgADCgkJCQAAAA==.Molsan:BAAALgAECgQJBAAAAA==.Monache:BAABLgAECn8ZAAIRAAgJdAtZLwBuAQARAAgJdAtZLwBuAQAAAA==.Mongalf:BAAALgADCgQJBAAAAA==.Montrois:BAAALgAECgQJBAAAAA==.Moopally:BAAALgAECgQJCAAAAA==.',
My='Mythrilblade:BAAALgAECgYJBgAAAA==.',
['Mô']='Môônmôôn:BAAALgADCgYJBgAAAA==.',
Ne='Neletheus:BAABLgAECn8WAAIcAAcJihBgbgBKAQAcAAcJihBgbgBKAQAAAA==.Nephbrew:BAAALgADCgEJAQAAAA==.Nephren:BAAALgADCgYJBgAAAA==.Nephwren:BAAALgADCgUJBQAAAA==.',
Ni='Nightparade:BAABLgAECn8aAAIXAAcJ1CC+MQAXAgAXAAcJ1CC+MQAXAgAAAA==.Nirvanik:BAAALgAECgQJBQAAAA==.Nishgrail:BAAALgADCgYJBAABLgAECgkJMAAYAMggAA==.',
Nu='Nukusmaximus:BAABLgAECn8eAAINAAgJCgiAiABNAQANAAgJCgiAiABNAQAAAA==.',
Ny='Nyeneave:BAAALgAECgIJAgAAAA==.Nyiah:BAABLgAECn8iAAILAAkJiBfeGQBVAgALAAkJiBfeGQBVAgAAAA==.',
['Nä']='Närgazeth:BAAALgADCgMJAwAAAA==.',
Og='Ogdoadtl:BAAALgAECgMJAwAAAA==.',
Oh='Ohello:BAAALgADCgUJBQAAAA==.',
Ol='Oldbull:BAAALgADCgEJAQAAAA==.',
On='Onex:BAAALgAECgYJCQAAAA==.',
Or='Organicmeat:BAAALgAECggJCQAAAA==.Orgrím:BAAALgADCgMJAwAAAA==.Ori:BAAALgAECgQJBQAAAA==.',
Pa='Paleprincess:BAAALgADCgIJAgABLgAECgIJBAAQAAAAAA==.Palii:BAAALgAECgQJBAAAAA==.Partywizard:BAAALgAECgMJAwAAAA==.',
Pe='Persefini:BAABLgAECn8UAAILAAcJaAuZUQApAQALAAcJaAuZUQApAQAAAA==.Persephoneia:BAAALgADCgcJDQAAAA==.Petrokull:BAAALgAECgMJAwAAAA==.',
Ph='Phaeder:BAAALgADCgUJBQAAAA==.Pheeguh:BAAALgADCgkJEAAAAA==.Pheylan:BAAALgAECgcJDwAAAA==.Philidox:BAAALgAECgYJCgABLgAECggJGwABAMwTAA==.Phood:BAAALgADCgcJBwABLgAECgEJAQAQAAAAAA==.',
Pi='Pikxs:BAAALgAECgMJAgAAAA==.Pitchou:BAAALgAECgUJBgAAAA==.',
Pl='Plugugly:BAAALgAECgQJBgAAAA==.',
Po='Poenin:BAAALgAECgEJAQAAAA==.Pokeball:BAAALgAECgYJDAAAAA==.Polinemarois:BAAALgADCggJBwAAAA==.Porkque:BAABLgAECn8fAAIPAAkJHQ3dRgCiAQAPAAkJHQ3dRgCiAQAAAA==.Potatobear:BAABLgAECn81AAQPAAkJviVJAQB1AwAPAAkJviVJAQB1AwAdAAYJXyPxGQBbAgAmAAkJYBp+CwBRAgAAAA==.',
Pr='Prifduwies:BAAALgADCgcJAQAAAA==.Professorson:BAAALgAECgMJBAAAAA==.',
Qi='Qiursi:BAAALgAECgUJBQAAAA==.',
Qu='Quicktime:BAABLgAECn88AAIKAAkJORwjEgCWAgAKAAkJORwjEgCWAgAAAA==.',
Ra='Ragedh:BAAALgAECggJEAAAAA==.Ragnarlothbr:BAAALgADCgQJBAAAAA==.Ragnoir:BAAALgAECggJEAAAAA==.Ranillan:BAAALgAECgYJBgAAAA==.Rased:BAAALgADCgEJAQAAAA==.Rashish:BAAALgADCgIJAgAAAA==.Ravies:BAAALgAFFAEJAQAAAA==.Rawdøg:BAAALgADCgEJAQAAAA==.Rayaz:BAAALgAECgUJCwABLgAECgkJFQALAEsXAA==.',
Re='Reeses:BAEALgAECgUJBQAAAA==.Reinhearts:BAAALgAFFAEJAQAAAA==.Religgar:BAABLgAECn8nAAIXAAgJahoHMwASAgAXAAgJahoHMwASAgAAAA==.Reploidzero:BAAALgAECgUJAQAAAA==.Rethart:BAAALgADCgcJBwAAAA==.',
Rh='Rhilik:BAAALgADCgQJBAAAAA==.',
Ri='Ricter:BAABLgAECn82AAINAAkJWRVjMwAvAgANAAkJWRVjMwAvAgAAAA==.Rictor:BAAALgAECgIJAwAAAA==.',
Ro='Roglof:BAABLgAECn8XAAINAAgJABNWYgCgAQANAAgJABNWYgCgAQAAAA==.Rokkoks:BAAALgADCggJEAAAAA==.Rowlah:BAAALgADCggJCgAAAA==.Roxyfoxy:BAAALgAECgYJCgABLgAECgcJBwAQAAAAAA==.Rozy:BAABLgAECn82AAMJAAkJGBtuEgB/AgAJAAkJGBtuEgB/AgAIAAUJnhGqvQDqAAAAAA==.',
Ru='Ruffs:BAABLgAECn8XAAMKAAkJIR0zFgB3AgAKAAkJIR0zFgB3AgASAAEJYhDAKgA1AAAAAA==.Ruiizu:BAABLgAECn8yAAIIAAkJJiT4BQAuAwAIAAkJJiT4BQAuAwAAAA==.Rulnathil:BAAALgADCgMJBgAAAA==.Rushuna:BAABLgAECn89AAIhAAkJextkCwCQAgAhAAkJextkCwCQAgAAAA==.',
Sa='Saberjaw:BAABLgAECn8XAAMmAAYJrBU3FACCAQAmAAYJkRQ3FACCAQAPAAIJvwvD5gBIAAAAAA==.Sairicck:BAABLgAECn8tAAIPAAkJcx78EQCZAgAPAAkJcx78EQCZAgAAAA==.Samaal:BAAALgADCgUJBQABLgAECgkJHwAWANYaAA==.Samial:BAAALgADCgYJDAABLgAECgkJHwAWANYaAA==.Sanguinor:BAAALgADCgYJFAAAAA==.Santamorte:BAAALgADCggJCgAAAA==.Sashay:BAAALgADCgYJCwAAAA==.Satoru:BAAALgAECgEJAgAAAA==.Satsuki:BAAALgADCgEJAQAAAA==.',
Sc='Scuba:BAAALgAECgUJCAAAAA==.',
Se='Selenar:BAAALgAECgEJAQAAAA==.Selesé:BAAALgAECgEJAQABLgAECggJEwAQAAAAAA==.Selinora:BAAALgAECgkJDgAAAA==.Serhalatath:BAAALgAECgYJCQAAAA==.',
Sh='Shadowsbane:BAAALgAECgIJAgAAAA==.Shaguar:BAABLgAECn8rAAMIAAkJ0CDcDADlAgAIAAkJ0CDcDADlAgAJAAcJPhCGXAALAQAAAA==.Shamhawk:BAAALgAECgEJAQAAAA==.Shaolinsnake:BAAALgAFFAIJAgAAAA==.Shiftace:BAAALgAECgEJAQABLgAECgEJAQAQAAAAAA==.Shiiva:BAAALgADCgMJAwAAAA==.Shizukahime:BAAALgAECgMJAwAAAA==.Shizzite:BAAALgADCgIJAgAAAA==.',
Si='Sicken:BAAALgADCgIJAgAAAA==.Sigiloc:BAAALgADCgcJBwAAAA==.Silverchair:BAAALgADCgQJBAAAAA==.Singe:BAACLgAFFH8JAAINAAQJnQNTZgDsAAANAAQJnQNTZgDsAAAuAAQKfyMAAg0ACAmWElxpAAMCAA0ACAmWElxpAAMCAAAA.Sinzala:BAABLgAECn8iAAINAAkJVR99FgC5AgANAAkJVR99FgC5AgAAAA==.',
Sk='Skeetsurfin:BAAALgAECgMJAwAAAA==.Skelly:BAAALgADCgYJCwAAAA==.Skyman:BAAALgADCgkJEwAAAA==.',
Sm='Smallblackdk:BAAALgAFFAEJAQAAAA==.Smaugdor:BAAALgADCgcJBgAAAA==.',
Sn='Snorp:BAAALgAECgQJBAAAAA==.Snowbunnyy:BAAALgAECgEJAQABLgAECgIJBAAQAAAAAA==.',
So='Solai:BAAALgAECgEJAQAAAA==.Solsti:BAABLgAECn8wAAIJAAkJ6xhREQBpAgAJAAkJ6xhREQBpAgAAAA==.',
Sp='Spears:BAAALgAECgYJEwAAAA==.Spoonbrew:BAAALgAECgYJBgABLgAFFAIJBQAXACIeAA==.Spoondot:BAABLgAECn8hAAMcAAgJ7yXEEQCpAgAcAAgJbSPEEQCpAgAiAAcJhyTeBwDRAQABLgAFFAIJBQAXACIeAA==.Spoonknight:BAACLgAFFH8FAAMXAAIJIh4djwC0AAAXAAIJIh4djwC0AAAjAAEJZAhZGgBDAAAuAAQKfxoAAyMACQl/IH8DAHMCABcACAnEHfEdAHUCACMACAmXH38DAHMCAAAA.',
Sq='Squidge:BAAALgAECgIJAgAAAA==.',
St='Staceyrella:BAAALgADCgMJAwAAAA==.Stainpngolin:BAABLgAECn8fAAIMAAgJUR32BwA9AgAMAAgJUR32BwA9AgAAAA==.Stillhorn:BAABLgAECn8hAAMKAAkJdRiGHgBCAgAKAAkJpReGHgBCAgAWAAQJxBfpLQDbAAAAAA==.Stinjeras:BAABLgAECn8yAAIcAAkJoSGDCQDzAgAcAAkJoSGDCQDzAgAAAA==.Stinkyjo:BAABLgAECn8yAAILAAkJbxrKDwC3AgALAAkJbxrKDwC3AgAAAA==.Stokelys:BAAALgADCgMJAwAAAA==.Stormfeather:BAAALgAECgEJAQAAAA==.Strikerv:BAACLgAFFH8HAAIPAAMJbQspSwDUAAAPAAMJbQspSwDUAAAuAAQKfyIAAg8ACQmGHvQWAHUCAA8ACQmGHvQWAHUCAAAA.',
Su='Sunadoria:BAAALgAECgUJEwAAAA==.Sunlite:BAAALgAECgEJAgAAAA==.Sunrae:BAABLgAECn8fAAQhAAgJIxetFAANAgAhAAgJWhWtFAANAgAHAAMJShQXXQC+AAAOAAUJcwkaVQCKAAAAAA==.Sushi:BAABLgAECn8fAAIYAAkJlRM4FQDlAQAYAAkJlRM4FQDlAQAAAA==.',
Sv='Sven:BAAALgAECgUJCQAAAA==.',
Sy='Sylinsor:BAAALgADCgEJAQAAAA==.Symor:BAAALgAECgMJBgAAAA==.',
['Sö']='Söap:BAAALgAECgUJBQAAAA==.',
Ta='Taggert:BAAALgAECgEJAQAAAA==.Tahl:BAABLgAECn8wAAIHAAcJRhItJACBAQAHAAcJRhItJACBAQAAAA==.Tamanovitch:BAAALgAECgEJAQAAAA==.Tamashii:BAAALgAECgUJBQABLgAFFAQJDAACAPIMAA==.Tangriah:BAAALgADCgEJAQAAAA==.Taproot:BAAALgADCgEJAQABLgAFFAQJEQANAA0LAA==.Taryen:BAAALgAECgQJBQABLgAECggJEAAQAAAAAA==.Tavie:BAABLgAFFH8QAAINAAQJ8xeoQABFAQANAAQJ8xeoQABFAQAAAA==.',
Te='Teddy:BAAALgADCgYJBgAAAA==.Tedo:BAAALgADCgcJDQABLgAFFAQJEAAJADEaAA==.Teikkas:BAAALgAECgYJCgAAAA==.Telaari:BAAALgAECgQJBgAAAA==.',
Th='Thalenia:BAACLgAFFH8GAAIPAAQJFQQ8PAD8AAAPAAQJFQQ8PAD8AAAuAAQKfygAAx0ACAm3CWgXANgAAA8ABwnQCixhAEQBAB0ACAlhBmgXANgAAAAA.Thallenia:BAAALgADCgEJAQAAAA==.Thalron:BAAALgADCgEJAgAAAA==.Thayne:BAAALgADCgEJAQAAAA==.Thekingdom:BAABLgAECn8eAAINAAgJVh1fRQBnAgANAAgJVh1fRQBnAgAAAA==.Thom:BAAALgADCgEJAQAAAA==.Thriller:BAAALgAECgUJCgABLgAFFAQJEAAJADEaAA==.',
Ti='Tikeidari:BAABLgAECn8/AAISAAkJViViAABWAwASAAkJViViAABWAwAAAA==.Tiltedtroll:BAABLgAECn8rAAIUAAkJnhJDIAC3AQAUAAkJnhJDIAC3AQAAAA==.Timedemon:BAABLgAECn8mAAIKAAkJcRvSIQAvAgAKAAkJcRvSIQAvAgAAAA==.Tinuveuil:BAAALgADCgYJBgAAAA==.',
To='Tonjuras:BAABLgAECn8dAAMnAAkJiB8xCgBeAgAnAAkJKBwxCgBeAgAgAAcJNRp9BwC/AQAAAA==.Toona:BAACLgAFFH8FAAIKAAIJ5AlDbwB0AAAKAAIJ5AlDbwB0AAAuAAQKfxwAAgoACQn7GgYcAKoCAAoACQn7GgYcAKoCAAEuAAQKCQkXABcAch8A.Torogrande:BAAALgADCgkJKgAAAA==.Touchmyting:BAAALgAECgEJAwAAAA==.Toutii:BAAALgAECgUJBgABLgAECgYJCgAQAAAAAA==.',
Tr='Trappydh:BAABLgAFFH8IAAISAAQJbRD7BADiAAASAAQJbRD7BADiAAABLgAFFAQJCAAfADkQAA==.Trappydk:BAACLgAFFH8IAAIfAAQJORDsFgD2AAAfAAQJORDsFgD2AAAuAAQKfxYAAh8ACAmFGlMRAMoBAB8ACAmFGlMRAMoBAAAA.Trintran:BAAALgADCgIJAgAAAA==.',
Tu='Tulshira:BAAALgADCgYJBgAAAA==.',
Tw='Twocents:BAABLgAECn8sAAMcAAgJsSStCwAdAwAcAAgJsSStCwAdAwAiAAEJAADgIQBqAAAAAA==.',
Ty='Tyraxus:BAAALgADCgkJEAAAAA==.Tyronne:BAAALgAECgcJBwAAAA==.',
['Tý']='Týr:BAAALgADCgQJBAAAAA==.',
Ul='Ultraball:BAAALgAECggJDwAAAA==.',
Un='Unagi:BAABLgAECn8pAAImAAgJeA8wGgCvAQAmAAgJeA8wGgCvAQAAAA==.Unkelb:BAAALgADCgYJBgAAAA==.',
Va='Vaenessa:BAABLgAECn8YAAINAAgJOAgIiABNAQANAAgJOAgIiABNAQAAAA==.Vaesir:BAAALgADCgcJDQAAAA==.Varleara:BAABLgAECn8gAAMKAAgJziFEEwDmAgAKAAgJziFEEwDmAgASAAEJKQeHLQAqAAAAAA==.',
Ve='Venenn:BAAALgADCgEJAgAAAA==.Venev:BAAALgAECgUJBgAAAA==.Ventana:BAABLgAECn8sAAIVAAgJhx/VBQBXAgAVAAgJhx/VBQBXAgAAAA==.Verdilac:BAABLgAECn8wAAIIAAkJIxviNwAEAgAIAAkJIxviNwAEAgABLgAFFAMJCQAkAHwgAA==.',
Vi='Vinceglortho:BAAALgAECgMJBwAAAA==.Vindicator:BAABLgAECn8fAAIIAAkJSB2OFwCZAgAIAAkJSB2OFwCZAgAAAA==.Violetnoir:BAAALgAECgQJBAABLgAECgcJGgAcANsIAA==.Visiroth:BAABLgAECn8bAAMXAAkJNQ2EVQCjAQAXAAkJJAuEVQCjAQAfAAMJVgrOOACGAAAAAA==.',
Vy='Vyyral:BAAALgAECgIJAgABLgAECgkJHwAWANYaAA==.',
Wa='Wagyumoo:BAAALgAECgEJAQABLgAFFAQJCQANAJ0DAA==.Wallydk:BAABLgAECn8oAAIXAAkJaxorGQCQAgAXAAkJaxorGQCQAgAAAA==.Wanji:BAABLgAECn8rAAIXAAkJCwtLVQCkAQAXAAkJCwtLVQCkAQAAAA==.',
We='Weave:BAAALgADCgYJBgAAAA==.Wenesday:BAAALgADCgYJCgAAAA==.Westhresh:BAAALgADCgcJBwAAAA==.',
Wi='Widginatrix:BAAALgAECggJEgAAAA==.Willkain:BAAALgAECgMJAwAAAA==.',
Wo='Woah:BAAALgAECgMJAwABLgAFFAIJBQAXACIeAA==.Woons:BAAALgAECgMJCAAAAA==.',
Wr='Wraithbane:BAAALgAECgMJAwAAAA==.',
Xa='Xaya:BAABLgAECn8aAAMcAAcJ2wgliQAVAQAcAAcJ2wgliQAVAQAbAAQJ6AJJUQB6AAAAAA==.',
Xe='Xenophorge:BAAALgADCgEJAQAAAA==.Xeralvezyn:BAAALgADCgkJCQAAAA==.',
Xi='Xiva:BAABLgAECn8hAAInAAYJchD9KAAkAQAnAAYJchD9KAAkAQAAAA==.',
Xo='Xovace:BAABLgAECn8WAAMWAAcJFwuzJgAMAQAWAAcJFwuzJgAMAQAKAAEJHwNkDQEcAAAAAA==.',
Xt='Xtayse:BAABLgAECn8iAAIDAAkJVR9RAQDXAgADAAkJVR9RAQDXAgAAAA==.',
Ya='Yagorbomb:BAAALgAECgEJAQAAAA==.Yamyam:BAABLgAECn8VAAIZAAkJsg/HKQCyAQAZAAkJsg/HKQCyAQAAAA==.',
Yi='Yirya:BAAALgADCgcJDwAAAA==.',
Yo='Yoruechi:BAACLgAFFH8JAAIMAAQJqhgoBwA2AQAMAAQJqhgoBwA2AQAuAAQKfyoAAgwACAkoI9gDALwCAAwACAkoI9gDALwCAAAA.',
['Yú']='Yúmyúm:BAABLgAECn8kAAIIAAkJWBfBOAABAgAIAAkJWBfBOAABAgAAAA==.',
Za='Zahel:BAABLgAECn8lAAIIAAkJjR1gJABUAgAIAAkJjR1gJABUAgAAAA==.Zahrogue:BAAALgADCgYJBgABLgAECgkJJQAIAI0dAA==.Zalark:BAAALgADCgUJCgABLgAECggJKQAHABkUAA==.Zangai:BAAALgADCgUJBQABLgAECggJGQARAHQLAA==.Zavier:BAAALgAECgEJAQAAAA==.',
Ze='Zeneri:BAABLgAECn8wAAMaAAkJdhAxGADKAQAaAAkJdhAxGADKAQAlAAkJEhC8IwDAAQAAAA==.',
Zo='Zobi:BAAALgAECgMJCAAAAA==.Zodius:BAAALgADCgEJAQAAAA==.Zomboo:BAAALgAFFAEJAQAAAA==.',
Zu='Zugzugzug:BAAALgADCgMJBgAAAA==.',
['Zò']='Zònan:BAAALgADCgEJAQABLgAECgkJKAATALITAA==.',
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
