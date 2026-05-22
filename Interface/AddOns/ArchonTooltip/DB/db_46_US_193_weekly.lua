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

local lookup = {'Evoker-Augmentation','Warrior-Arms','Warrior-Fury','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Unknown-Unknown','Warlock-Demonology','Mage-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Paladin-Retribution','Monk-Brewmaster','Hunter-BeastMastery','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Paladin-Holy','Warlock-Destruction','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','DemonHunter-Devourer','Warlock-Affliction','DemonHunter-Vengeance','Priest-Discipline','Druid-Guardian','DemonHunter-Havoc','Druid-Restoration','Hunter-Survival','Shaman-Enhancement','Paladin-Protection','Druid-Feral','DeathKnight-Frost','Druid-Balance','Monk-Mistweaver','Mage-Arcane',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abchi:BAAALgAECgMJAwAAAA==.Abelladanger:BAAALgADCgYJBgAAAA==.Absorption:BAAALgAECggJDAABLgAECggJIQABAFYXAA==.',
Ac='Ackerw:BAABLgAFFH8JAAMCAAQJkws1BAD3AAACAAQJkws1BAD3AAADAAEJaQQvJABMAAAAAA==.',
Ad='Addilyn:BAABLgAECn8aAAMEAAgJPxT+JQBOAQAEAAgJPxT+JQBOAQAFAAcJcgtXKgAsAQAAAA==.',
Ah='Ahminous:BAABLgAECn8aAAIGAAgJ2BM9FQBOAQAGAAgJ2BM9FQBOAQAAAA==.Ahroo:BAAALgAECgkJGQAAAQ==.Ahrue:BAAALgAECgkJDQABLgAECgkJGQAHAAAAAQ==.',
Ai='Airc:BAAALgAECgYJDwAAAA==.Aiurman:BAAALgADCgkJCQAAAA==.',
Al='Alfster:BAABLgAECn8fAAIIAAkJNAfSUgBmAQAIAAkJNAfSUgBmAQAAAA==.Allessiae:BAAALgAECgYJBgAAAA==.Alvar:BAABLgAECn8ZAAIIAAgJ/RIFRgCMAQAIAAgJ/RIFRgCMAQAAAA==.',
Ar='Arcadium:BAABLgAECn8VAAIJAAUJWCKWbwD1AQAJAAUJWCKWbwD1AQAAAA==.Arkhan:BAAALgAECgQJBAAAAA==.Arêos:BAABLgAECn8eAAIEAAkJZh0ZCQCPAgAEAAkJZh0ZCQCPAgAAAA==.',
As='Asunaish:BAABLgAECn8YAAIKAAgJThsPMQD1AQAKAAgJThsPMQD1AQAAAA==.',
At='Atiko:BAAALgADCgQJBAAAAA==.Atomicrednax:BAABLgAFFH8ZAAILAAcJAB/AAQAkAgALAAcJAB/AAQAkAgAAAA==.Atropos:BAAALgADCgcJBwAAAA==.',
Ay='Ayisen:BAAALgAECgQJBgAAAA==.',
Az='Azarite:BAABLgAECn8sAAIMAAkJrRE/RACzAQAMAAkJrRE/RACzAQAAAA==.',
Ba='Babybilly:BAAALgAECgQJBwAAAA==.Badassbum:BAAALgAECgYJEgAAAA==.Bahoodies:BAAALgAECgcJBgAAAA==.Balgorath:BAAALgAECgQJBwAAAA==.Balthazar:BAAALgADCgUJBgAAAA==.Bananastand:BAAALgADCgMJAwAAAA==.Banree:BAAALgAECgEJAwAAAA==.Bassa:BAAALgADCgYJBgAAAA==.Battman:BAAALgADCgcJDAABLgAECgEJAQAHAAAAAA==.Battousaiha:BAABLgAECn8cAAIMAAgJABobMwDuAQAMAAgJABobMwDuAQAAAA==.',
Be='Bera:BAAALgAECgIJAwAAAA==.',
Bi='Bigmustard:BAACLgAFFH8iAAINAAcJUx+TAgAIAgANAAcJUx+TAgAIAgAuAAQKfywAAg0ACQkvJfQDAFADAA0ACQkvJfQDAFADAAAA.Bignut:BAAALgAECgcJBgAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Borticuss:BAAALgAECgMJAwABLgAECgcJJQANAA8aAA==.Bortikus:BAAALgAECgQJBwABLgAECgcJJQANAA8aAA==.Boskos:BAAALgADCgQJBAABLgAECgQJCQAHAAAAAA==.Bossnugg:BAAALgADCgYJCAABLgAECgQJCQAHAAAAAA==.',
Br='Brasputin:BAAALgADCgQJBAAAAA==.Breez:BAAALgADCgIJAgAAAA==.',
Bu='Bul:BAAALgADCgcJBwABLgAECggJFAAOABAUAA==.Bullshifting:BAAALgAECgcJEwAAAA==.Bumbaloo:BAAALgAECgQJBQAAAA==.Burgi:BAAALgAECgQJBQAAAA==.Burney:BAABLgAECn8sAAMPAAgJRSK1AgD9AgAPAAgJRSK1AgD9AgAQAAIJcAtVFgBlAAAAAA==.',
['Bò']='Bònesaw:BAACLgAFFH8FAAIRAAIJuCKzEgDDAAARAAIJuCKzEgDDAAAuAAQKfy0AAhEACQl0IrICAOMCABEACQl0IrICAOMCAAAA.',
Ca='Calibrium:BAAALgAECgYJDwAAAA==.Cannaboss:BAAALgAECgQJCQAAAA==.Carll:BAACLgAFFH8MAAISAAQJExLWIQDGAAASAAQJExLWIQDGAAAuAAQKfx8AAhIACAlsFL4mAPQBABIACAlsFL4mAPQBAAAA.Catleesei:BAABLgAECn8bAAIBAAkJVRA8GwCtAQABAAkJVRA8GwCtAQAAAA==.',
Ch='Chables:BAAALgADCgcJBwAAAA==.Chai:BAAALgAECgYJEQAAAA==.Chaosmage:BAAALgAECgQJBAAAAA==.Charizard:BAAALgAECgIJAwAAAA==.Chickyn:BAAALgAECgMJBQAAAA==.Chinsei:BAAALgAECgEJAQAAAA==.Choppa:BAAALgAECgQJCAAAAA==.',
Cl='Clyde:BAAALgAECgIJAgAAAA==.',
Co='Cocodruid:BAAALgAECgYJCQAAAA==.Coldxlxsoul:BAABLgAECn8WAAMQAAcJqhQNFAClAQAQAAcJDRINFAClAQABAAYJWBE/LgBQAQAAAA==.Condrius:BAAALgADCgUJBgAAAA==.Convict:BAAALgAECgMJBQAAAA==.',
Cr='Crappylock:BAAALgAECgQJBAAAAA==.Criotor:BAAALgAECgIJBAAAAA==.Critster:BAAALgAECgQJBwAAAA==.Crud:BAAALgADCgMJAwAAAA==.',
Da='Daddy:BAACLgAFFH8NAAIIAAYJ6QtUHQBnAQAIAAYJ6QtUHQBnAQAuAAQKfyUAAwgACAk0GvYoAG0CAAgACAn1GfYoAG0CABMABwlaFJsYAIYBAAAA.Darkportal:BAAALgAECgQJCQABLgAECggJGAAKAE4bAA==.Datnagablu:BAAALgAECgQJBQAAAA==.',
De='Deathsrain:BAABLgAECn8kAAIKAAgJ2x/DNABkAgAKAAgJ2x/DNABkAgAAAA==.Decimez:BAABLgAECn8aAAIUAAgJMiCMDQBFAgAUAAgJMiCMDQBFAgAAAA==.Decimock:BAAALgAECggJCQAAAA==.Delisa:BAAALgAECgYJBgAAAA==.Dellinsane:BAAALgAECgEJAQAAAA==.Devour:BAAALgAFFAIJAwAAAA==.',
Di='Dingiswayo:BAAALgAECgcJEgAAAA==.Dipz:BAAALgAECgYJCQAAAA==.',
Do='Donyolerberz:BAAALgAECgcJBgAAAA==.',
Dr='Draeno:BAABLgAECn8UAAIOAAgJEBSSUQBVAQAOAAgJEBSSUQBVAQAAAA==.Dragonflyy:BAAALgAECgEJAQAAAA==.Dragonips:BAAALgADCgYJBgAAAA==.Drbonedaddy:BAAALgAECgYJBgABLgAECgcJBQAHAAAAAA==.Drinkyds:BAABLgAFFH8HAAIVAAUJ5RYHCwCjAQAVAAUJ5RYHCwCjAQAAAA==.',
Du='Duggnut:BAAALgAECgMJAwAAAA==.Durgi:BAABLgAECn8aAAISAAcJUhs+JQD8AQASAAcJUhs+JQD8AQAAAA==.Durtrim:BAAALgADCgIJAgAAAA==.',
Ed='Ederen:BAAALgAECgEJAQAAAA==.',
Ee='Eepic:BAABLgAECn8yAAIMAAkJ4REpOgDTAQAMAAkJ4REpOgDTAQAAAA==.',
Ei='Eightmile:BAAALgAECgcJCAAAAA==.Eisenhorn:BAAALgADCgcJDAABLgAECgcJFgAQAKoUAA==.',
El='Elementfrost:BAAALgAECgEJAQAAAA==.Ellio:BAAALgADCgcJBwABLgAFFAYJFAAOAOMcAA==.',
Em='Embar:BAAALgADCgIJAwAAAA==.Emrys:BAACLgAFFH8IAAMNAAIJ1CSfJwDWAAANAAIJ1CSfJwDWAAAWAAEJswltKABCAAAuAAQKfxgAAw0ABwkvJDYYAEMCAA0ABwkvJDYYAEMCABYABAnOEBdSAMoAAAAA.',
Ep='Epinephrine:BAAALgAECggJDgAAAA==.',
Er='Eriebus:BAABLgAECn8aAAIXAAgJ5gvgXgAcAQAXAAgJ5gvgXgAcAQAAAA==.Erona:BAAALgAECgYJCgAAAA==.',
Es='Escorpiøn:BAACLgAFFH8OAAIKAAQJyB0VMAD9AAAKAAQJyB0VMAD9AAAuAAQKfygAAgoACAkdJMEPALMCAAoACAkdJMEPALMCAAAA.',
Ev='Evenstar:BAAALgAECgEJAQAAAA==.',
Fa='Faling:BAAALgADCgYJEQAAAA==.Falkor:BAAALgAECgcJEAABLgAECggJGAAKAE4bAA==.Fartcloud:BAAALgAECgUJBQAAAA==.Fatigued:BAAALgAECggJDQAAAA==.',
Fe='Feech:BAAALgAECgUJDAABLgAFFAMJCQAYAFobAA==.Feerz:BAAALgAECgIJAgAAAA==.Felagain:BAABLgAECn8jAAIZAAgJ6AqaDQAkAQAZAAgJ6AqaDQAkAQAAAA==.Felslizer:BAAALgAECgMJAwAAAA==.Fentuul:BAAALgADCgkJCQAAAA==.Ferrous:BAAALgAECgEJAQAAAA==.',
Fl='Flankshot:BAACLgAFFH8FAAIJAAIJuwb+ewCWAAAJAAIJuwb+ewCWAAAuAAQKfyQAAgkACQkTDjRHAMQBAAkACQkTDjRHAMQBAAAA.Flo:BAAALgADCgUJBgABLgAECgcJBgAHAAAAAA==.Flõ:BAAALgAECgQJBAAAAA==.',
Fo='Foops:BAACLgAFFH8gAAIJAAcJHRgoBAAvAgAJAAcJHRgoBAAvAgAuAAQKfxcAAgkACAlhHSRGAGUCAAkACAlhHSRGAGUCAAAA.Foopsadin:BAAALgAECgYJDQABLgAFFAcJIAAJAB0YAA==.',
Fr='Frinek:BAAALgADCgkJCQAAAA==.',
Fu='Fumin:BAAALgAECgQJCgAAAA==.',
Ga='Galibuk:BAAALgADCgYJBgAAAA==.',
Ge='Geezuss:BAAALgAECgEJBAABLgAFFAMJBQAaAJUIAA==.Genohbreaker:BAAALgAECgEJAQAAAA==.Genosaur:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.Getrkt:BAAALgAECgQJBAAAAA==.',
Gh='Ghouliver:BAABLgAECn8rAAIKAAkJpRfWKwALAgAKAAkJpRfWKwALAgAAAA==.',
Gi='Gigasushi:BAAALgAECgQJBAAAAA==.Gimblie:BAABLgAECn8dAAIEAAgJ5RSlGgCsAQAEAAgJ5RSlGgCsAQAAAA==.Gimermonty:BAACLgAFFH8FAAIOAAIJeRdwRwCmAAAOAAIJeRdwRwCmAAAuAAQKfysAAg4ACQmXHYsNAKACAA4ACQmXHYsNAKACAAAA.Ging:BAAALgADCgcJCAAAAA==.',
Gl='Glorfindel:BAAALgAECgcJCAAAAA==.',
Go='Goblinkicker:BAAALgAECgMJBAAAAA==.Gothegg:BAAALgAECgEJAgAAAA==.Gothmommy:BAABLgAECn8eAAIIAAgJTQodYABDAQAIAAgJTQodYABDAQAAAA==.',
Gr='Gregiously:BAAALgAECgkJCQAAAA==.Gronk:BAAALgAECgIJAgAAAA==.',
Gu='Guldanshower:BAABLgAECn8hAAMTAAgJlRpCDgDjAQATAAYJJxxCDgDjAQAIAAcJqBbkOwCtAQAAAA==.',
Ha='Habusaki:BAAALgAECgQJBgAAAA==.Hakal:BAABLgAECn8kAAIbAAgJRhhFCwDHAQAbAAgJRhhFCwDHAQAAAA==.Halvor:BAAALgAECgQJCAAAAA==.Hangbladz:BAAALgAECgcJEwAAAA==.Hardwarë:BAAALgAECgEJAQAAAA==.Harrygazm:BAAALgADCgQJBAAAAA==.',
He='Healista:BAAALgADCgYJBgABLgAECgkJKAAcAEwbAA==.',
Hu='Hukdemon:BAABLgAECn8aAAIZAAgJNSS+AQDAAgAZAAgJNSS+AQDAAgAAAA==.',
Ic='Iceandfire:BAAALgAECgEJAQAAAA==.',
Il='Illiyana:BAAALgAECgcJBwAAAA==.',
In='Inviteme:BAAALgADCgMJAwABLgAECgkJIwAKABYaAA==.',
Ja='Jakesterwars:BAAALgADCgEJAQAAAA==.Jaldore:BAAALgADCgcJBwAAAA==.',
Je='Jeaine:BAAALgAECgEJAQAAAA==.',
Jh='Jhamin:BAACLgAFFH8NAAMUAAQJFA+fFgAaAQAUAAQJFA+fFgAaAQAVAAMJfgkDNAC1AAAuAAQKfyEAAxUACAmjFXMiABACABUACAmjFXMiABACABQABAkvGR88AO0AAAAA.',
Ji='Jiveturkey:BAAALgAECgQJAwAAAA==.',
Ju='Jubeiskyfang:BAAALgAECgcJCAABLgAFFAQJBQAMAEMPAA==.Julkaal:BAAALgAECgEJAQAAAA==.Junlelon:BAAALgAECgEJAQAAAA==.',
Ka='Kaedrelyn:BAAALgAECgEJAQAAAA==.Kai:BAAALgAECgYJBwAAAA==.Karnage:BAAALgAECgcJCAAAAA==.Karney:BAAALgAECgEJAwAAAA==.Kazam:BAAALgAECgYJBgAAAA==.Kazik:BAABLgAECn8ZAAIXAAcJaBuuNwCeAQAXAAcJaBuuNwCeAQAAAA==.',
Ke='Kelrath:BAABLgAECn8lAAIdAAgJvw7VMwCGAQAdAAgJvw7VMwCGAQAAAA==.Kelthugan:BAAALgADCgIJAgAAAA==.Kendeez:BAAALgADCgcJCwAAAA==.Kenparrchi:BAAALgAECgIJAwAAAA==.Kensei:BAAALgADCgIJAgABLgAECgkJFQAMAA4UAA==.Ketheric:BAAALgADCgYJCAAAAA==.',
Ki='Kindinos:BAABLgAECn8WAAMOAAYJXxHWYgAlAQAOAAUJXxHWYgAlAQALAAUJIg3XGACRAAAAAA==.',
Kl='Kllcky:BAABLgAECn8fAAIMAAgJTSPaCQDmAgAMAAgJTSPaCQDmAgABLgAFFAMJCQAYAFobAA==.Klorox:BAAALgAECgIJAgAAAA==.',
Kr='Kraoptix:BAAALgAECgEJAQAAAA==.Kratøs:BAAALgADCgMJAwAAAA==.Kraun:BAABLgAECn8nAAMeAAcJviHxCwATAgAeAAYJVCLxCwATAgAOAAMJrx5SeADxAAAAAA==.Kreig:BAAALgADCgIJAgAAAA==.Kroo:BAAALgAECgYJDQABLgAECggJIQABAFYXAA==.Krythas:BAAALgADCgIJAgAAAA==.',
Ku='Kuwabara:BAAALgADCgUJBQAAAA==.',
Kv='Kvothè:BAAALgAECgcJDwAAAA==.',
Ky='Kyi:BAACLgAFFH8FAAIWAAIJ8wm8HwCDAAAWAAIJ8wm8HwCDAAAuAAQKfyAAAhYACQkfE/QWAK0BABYACQkfE/QWAK0BAAAA.',
['Kî']='Kîrîto:BAAALgAECgIJBQABLgAECggJFAAJAGMeAA==.',
La='Lactosetwo:BAAALgAECgQJBQABLgAECgYJCQAHAAAAAA==.Lammlock:BAAALgAECgIJAgAAAA==.Landar:BAABLgAECn88AAIdAAkJJRZEFQBYAgAdAAkJJRZEFQBYAgAAAA==.Lathindra:BAAALgAECgEJAgAAAA==.Lazerpony:BAAALgAECgEJAwABLgAECgQJBwAHAAAAAA==.',
Le='Lefordini:BAAALgAECgQJBAAAAA==.Leggomyâggro:BAAALgAECgcJDwABLgAFFAQJDwAOALkSAA==.Legun:BAAALgADCgMJAwAAAA==.Lexicon:BAAALgAECgMJAwAAAA==.',
Li='Liara:BAABLgAECn8oAAIeAAkJvA8fDgAGAgAeAAkJvA8fDgAGAgAAAA==.Lireesa:BAABLgAECn8jAAITAAgJmRCkCQBcAQATAAgJmRCkCQBcAQAAAA==.Lithiandriel:BAAALgAECgYJEgAAAA==.Liçk:BAAALgAECgMJAwABLgAECggJHAAdADkcAA==.',
Lo='Lockonyou:BAAALgAECgYJEQAAAA==.Logeofford:BAAALgADCgYJBQAAAA==.Lolola:BAAALgAECgQJBAAAAA==.Losthack:BAAALgAECgEJAQAAAA==.',
Lu='Lucker:BAAALgAECgEJAQAAAA==.Lunn:BAABLgAECn8YAAILAAcJug+wEADfAAALAAcJug+wEADfAAAAAA==.Lurac:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.',
Ma='Madhi:BAAALgADCgcJDQAAAA==.Mahk:BAABLgAECn8UAAIMAAcJixXMXQBuAQAMAAcJixXMXQBuAQAAAA==.Majin:BAAALgAECgMJAwABLgAECgkJFQAMAA4UAA==.Mangreese:BAABLgAECn8dAAIfAAkJ7g7lCgCgAQAfAAkJ7g7lCgCgAQAAAA==.Matelk:BAAALgAECgEJAgAAAA==.',
Me='Meekseek:BAAALgAECgQJDgAAAA==.Meltdown:BAAALgADCgQJBAAAAA==.Memoo:BAAALgADCgUJBQAAAA==.',
Mi='Miahealifa:BAABLgAECn8YAAMEAAcJOQtaRwAcAQAEAAYJgAlaRwAcAQAaAAYJLAmoMgDsAAAAAA==.Milim:BAAALgAECgUJBQAAAA==.Miloh:BAAALgAECgQJCQAAAA==.Mistabubbles:BAAALgAECgYJBgAAAA==.Mistmia:BAAALgADCgYJBgAAAA==.Mixmasterg:BAABLgAECn8fAAIXAAgJFgyzVgAzAQAXAAgJFgyzVgAzAQAAAA==.',
Mo='Mograinez:BAACLgAFFH8eAAIKAAcJpCVyAACEAgAKAAcJpCVyAACEAgAuAAQKfxUAAgoACAl9JqUcANMCAAoACAl9JqUcANMCAAAA.Monkeyman:BAAALgADCgIJAgAAAA==.Moosebreath:BAAALgAECgQJBAABLgAFFAUJBQAaAEgHAA==.',
Mu='Murderer:BAAALgAECgMJBgAAAA==.',
My='Mythunrus:BAABLgAECn8YAAIcAAYJIhI+MgBDAQAcAAYJIhI+MgBDAQAAAA==.',
['Mó']='Móñk:BAAALgAECgcJEgAAAA==.',
['Mö']='Mörgana:BAAALgADCgQJBAAAAA==.',
Na='Narofu:BAAALgADCgQJBAAAAA==.Nazurasar:BAAALgAECgMJAwAAAA==.',
Ne='Nejìre:BAAALgADCgYJCQAAAA==.Neteyam:BAAALgAECgYJCAAAAA==.Neutron:BAAALgAECgMJBQAAAA==.',
No='Norolock:BAABLgAECn8aAAIIAAgJlRbMOQC1AQAIAAgJlRbMOQC1AQAAAA==.Notbreeze:BAAALgADCgYJBgAAAA==.Notsure:BAAALgAECgcJCAAAAA==.',
Nu='Nuero:BAAALgAFFAIJBAAAAA==.Nukashine:BAAALgADCgYJCAAAAA==.Nuuro:BAAALgAECgcJEgAAAA==.',
Ny='Ny:BAAALgADCgUJBQAAAA==.Nyverra:BAAALgADCgQJBAAAAA==.',
['Nã']='Nãrcissus:BAACLgAFFH8JAAMYAAMJWhtZAwBfAAAIAAIJrxmkZgClAAAYAAEJrx5ZAwBfAAAuAAQKfy0ABAgACAkHIAozAM8BAAgABgn4HwozAM8BABMABAkoF3IuAAIBABgAAwnQIDAWANEAAAAA.',
Ol='Oldshotz:BAAALgAECgYJDAAAAA==.',
Om='Omgsteak:BAAALgAECgYJDwAAAA==.',
On='Onapalehorse:BAAALgADCgcJEAAAAA==.Onger:BAAALgADCgEJAQAAAA==.Onlybusa:BAAALgAECgEJAwAAAA==.Ons:BAAALgAECgQJBAAAAA==.',
Ow='Owl:BAAALgAECgEJAQABLgAECgcJGQAMAJMTAA==.',
Pa='Panpots:BAAALgADCgYJBgAAAA==.Panzerdox:BAAALgAECgcJBwAAAA==.Panzerwolf:BAECLgAFFH8bAAIRAAUJqSVPAwC6AQARAAUJqSVPAwC6AQAuAAQKf1kAAxEACQllJlcAAHUDABEACQllJlcAAHUDAAMABQmGB2pvAPoAAAAA.Patchnotes:BAAALgAECgYJCwAAAA==.',
Pe='Peepaw:BAAALgAFFAIJAgAAAA==.',
Po='Poorclass:BAAALgAECgEJAQAAAA==.',
Pr='Pray:BAAALgAECgIJAgAAAA==.Prayforme:BAABLgAECn8gAAMaAAgJAhz0CQCBAgAaAAgJAhz0CQCBAgAFAAQJ4BONNADzAAAAAA==.Prettynails:BAAALgAECggJDwAAAA==.Prise:BAACLgAFFH8FAAMIAAMJVA8gaQChAAAIAAIJoBYgaQChAAATAAEJvQAGHgAoAAAuAAQKfxYAAxMABwk5EQQbAHUBABMABwm+EAQbAHUBAAgABglHDrmqAKsAAAAA.',
Ps='Psilocybic:BAABLgAECn8aAAMVAAkJdQmpSQBbAQAVAAkJdQmpSQBbAQAUAAYJ4wfqTwAHAQAAAA==.',
Qw='Qweh:BAAALgAECgYJDwAAAA==.',
Ra='Rahnko:BAAALgAECgQJAgAAAA==.Rakkasei:BAACLgAFFH8FAAIBAAIJWwd5OgCCAAABAAIJWwd5OgCCAAAuAAQKfx4AAwEACQm5F0sVAOUBAAEACQm5F0sVAOUBABAAAwn+BPUyAH4AAAAA.Ralthas:BAAALgAECgQJBwAAAA==.Randark:BAABLgAECn8nAAQCAAgJhRr5CgD0AQACAAYJCx35CgD0AQADAAcJ0g83TwBqAQARAAYJOxTuHQD3AAAAAA==.Ravenoth:BAAALgAECgEJAQAAAA==.Razkal:BAAALgAECgYJDQAAAA==.Razzlock:BAAALgADCgcJBwAAAA==.',
Re='Reshiiram:BAAALgAECgEJAQAAAA==.Retneprac:BAAALgADCgQJBAAAAA==.Revirginator:BAABLgAECn8hAAMgAAcJewn8JADgAAAgAAcJPgb8JADgAAAMAAQJ0QtBzgCkAAAAAA==.Revna:BAAALgAECgEJAwAAAA==.',
Rh='Rhagnar:BAAALgAECgQJBAAAAA==.',
Ri='Richandfamus:BAABLgAECn8XAAIKAAUJzB8nZQBVAQAKAAUJzB8nZQBVAQAAAA==.Riftstalker:BAABLgAECn8XAAMeAAcJCBdwEAC9AQAeAAcJCBdwEAC9AQAOAAEJ+w0f0QA1AAAAAA==.',
Rn='Rngesus:BAACLgAFFH8JAAIIAAMJ/BBuTwDgAAAIAAMJ/BBuTwDgAAAuAAQKfyUAAwgACQl4HnEfACwCAAgACQl4HnEfACwCABMAAgliBsNWAGoAAAAA.',
Ro='Rocmaul:BAAALgADCgkJCQAAAA==.',
Ru='Rushem:BAAALgAECggJEwAAAA==.Ruwa:BAAALgADCgUJBQAAAA==.',
Ry='Ryft:BAABLgAECn8XAAIKAAgJzBYbegCQAQAKAAgJzBYbegCQAQAAAA==.Ryhaz:BAAALgADCgcJBwAAAA==.',
Sa='Saenen:BAABLgAECn8WAAIhAAcJuQsaFwD4AAAhAAcJuQsaFwD4AAAAAA==.Samitsu:BAAALgAECgEJAQAAAA==.Sandrozarke:BAABLgAECn8hAAQBAAgJVhc7EQBlAgABAAgJPxc7EQBlAgAQAAEJ+RJXPAA8AAAPAAEJygJtRwA4AAAAAA==.Sarah:BAAALgAECgIJAgABLgAFFAMJBgAaAHkXAA==.',
Sc='Scorchi:BAAALgAECgEJAQABLgAECgEJAwAHAAAAAA==.Scrublet:BAAALgAECgYJEAAAAA==.',
Se='Seldara:BAABLgAECn8lAAMiAAgJzwWnDgC5AAAKAAgJaQPotAC+AAAiAAQJwwinDgC5AAAAAA==.Seraphic:BAAALgAECgkJBAAAAA==.Serenity:BAABLgAECn8bAAIaAAUJUCEuFgDQAQAaAAUJUCEuFgDQAQAAAA==.Sergeyred:BAAALgADCgUJBQAAAA==.Serlyn:BAAALgAECgYJEAAAAA==.Seseria:BAACLgAFFH8FAAMSAAIJNA1nLAB7AAASAAIJNA1nLAB7AAAgAAIJIAQjDQBTAAAuAAQKfywAAyAACQmQFeYPAHABACAACAnpE+YPAHABABIABQliFc40AC8BAAAA.Sevinofnine:BAAALgAECgEJAQAAAA==.',
Sh='Shalamar:BAAALgAECgEJBAAAAA==.Shanic:BAABLgAECn8YAAIjAAgJ0xd7FQDRAQAjAAgJ0xd7FQDRAQAAAA==.Shiddybill:BAAALgAECgQJBAAAAA==.Shiftor:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.Shiftyslice:BAAALgAECgEJAgAAAA==.Shihiro:BAAALgADCgIJAQAAAA==.',
Si='Siberianbull:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgEJAgAAAA==.',
Sl='Slaveman:BAAALgAECgIJAgAAAA==.Slitherina:BAAALgADCgYJBgAAAA==.Slåkritisk:BAABLgAECn8XAAIeAAgJaA1bEgCdAQAeAAgJaA1bEgCdAQAAAA==.',
Sm='Smitervane:BAAALgADCgcJDQAAAA==.Smogy:BAAALgAECgcJCQAAAA==.',
Sn='Snipyterror:BAAALgADCgEJAQAAAA==.Snoodly:BAABLgAECn8VAAIkAAgJhxAUIgCMAQAkAAgJhxAUIgCMAQAAAA==.',
So='Solarice:BAABLgAECn8gAAMJAAkJWB51EADFAgAJAAkJJR51EADFAgAlAAEJ5iBkGQBMAAAAAA==.Soletaken:BAAALgADCgQJBwAAAA==.Solunais:BAABLgAECn8iAAIIAAkJuwsuQwCVAQAIAAkJuwsuQwCVAQAAAA==.Soramor:BAAALgADCgcJCAAAAA==.Sorynn:BAAALgAECgEJAQAAAA==.',
Sp='Spirallidan:BAACLgAFFH8EAAIXAAIJGAPWYQByAAAXAAIJGAPWYQByAAAuAAQKfxYAAhcACQkNEyZLAMgBABcACQkNEyZLAMgBAAAA.Spy:BAAALgADCgQJBAAAAA==.',
St='Stardor:BAAALgAECgkJCAAAAA==.Staticprot:BAABLgAFFH8FAAIRAAQJzgthEwC7AAARAAQJzgthEwC7AAAAAA==.Staticsrexar:BAAALgADCgcJBwABLgAFFAQJBQARAM4LAA==.Stature:BAAALgAECgcJBwAAAA==.Stepbro:BAABLgAECn8jAAIKAAkJFhoiHgBRAgAKAAkJFhoiHgBRAgAAAA==.Stinksauce:BAACLgAFFH8OAAIPAAQJTR4IDgBUAQAPAAQJTR4IDgBUAQAuAAQKfxoABA8ACQkHGm4NAGACAA8ACQkHGm4NAGACAAEAAQl0BtRhADUAABAAAQmvB4A/ADIAAAAA.Stormvetra:BAAALgAECgQJBQAAAA==.',
Su='Supabox:BAAALgAECgcJEgABLgAFFAUJFQANACElAA==.Superchunk:BAAALgAECgEJAQAAAA==.Supermann:BAAALgAECgEJAQAAAA==.Suryoudie:BAAALgADCgQJBAAAAA==.Sutra:BAABLgAECn8YAAIEAAcJYwshLgAUAQAEAAcJYwshLgAUAQAAAA==.',
Sw='Swiftmend:BAAALgAECgYJBgABLgAECggJDQAHAAAAAA==.',
Sy='Sylmarillion:BAABLgAECn8jAAISAAgJrxrMEwAoAgASAAgJrxrMEwAoAgAAAA==.',
['Sø']='Sørry:BAABLgAECn8XAAINAAcJkRmcFwCwAQANAAcJkRmcFwCwAQAAAA==.',
Ta='Talgulen:BAABLgAECn8vAAIQAAkJXh2OAQCcAgAQAAkJXh2OAQCcAgAAAA==.Tankytauren:BAABLgAECn8lAAMKAAkJJBI/TwCQAQAKAAgJFRI/TwCQAQAiAAcJzA6wCABaAQAAAA==.Tarquinius:BAABLgAECn8nAAIcAAkJUQ8lFACNAQAcAAkJUQ8lFACNAQAAAA==.Tatianasoles:BAAALgAECgEJAQAAAA==.Taxii:BAAALgAECgUJCQABLgAECgkJLwADAGMlAA==.Taylorswifft:BAAALgAECgcJAQAAAA==.',
Te='Telanastre:BAAALgAECgQJBwAAAA==.',
Th='Tharos:BAAALgADCgEJAgAAAA==.Theat:BAAALgAECgQJDAAAAA==.Theoeicke:BAAALgAECgcJDAABLgAFFAIJBQAWAPMJAA==.Thibbledor:BAAALgADCgkJFAABLgAECgcJFQAUAJYUAA==.',
Ti='Tifferny:BAAALgAECgIJBQAAAA==.Tiffèrny:BAAALgAECgYJBgAAAA==.Tinydrunk:BAAALgADCggJCAAAAA==.',
To='Tondra:BAAALgAECgYJCQAAAA==.Tone:BAABLgAECn8dAAMjAAgJIBRaLQCZAQAjAAcJkxNaLQCZAQAdAAgJ+Q/pPgBPAQAAAA==.Tonkatruck:BAAALgAECgYJBQAAAA==.Totemlycool:BAABLgAECn8gAAQUAAgJGxWwIAAKAgAUAAgJCRSwIAAKAgAfAAYJlRcEEgCWAQAVAAIJhAGWkwBNAAABLgAECggJIQABAFYXAA==.',
Tr='Trappress:BAAALgAECggJDQABLgAECgkJPQAdAAscAA==.Treehuggër:BAAALgAECgkJDQAAAA==.Trowa:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.Trowaz:BAAALgAFFAEJAQAAAA==.Truffles:BAAALgADCgQJBAABLgAECggJIQATAJUaAA==.Tryrah:BAABLgAFFH8VAAIjAAcJaxaGAwDtAQAjAAcJaxaGAwDtAQAAAA==.',
Tw='Twinsons:BAAALgADCgEJAQAAAA==.Twisty:BAAALgAECgQJBQABLgAFFAEJAQAHAAAAAA==.Twîsty:BAAALgAECgUJBgABLgAFFAEJAQAHAAAAAA==.',
Ty='Tygron:BAAALgADCgQJBAAAAA==.Tyleroth:BAABLgAECn8gAAIXAAkJYhLWOwCNAQAXAAkJYhLWOwCNAQAAAA==.Tyrasia:BAAALgAECgEJAgAAAA==.Tyrith:BAABLgAECn8WAAMDAAgJsxhHPgCrAQADAAcJ4hhHPgCrAQACAAMJrRcNIgDcAAAAAA==.',
['Tö']='Töömis:BAABLgAECn8ZAAIMAAcJkxOFfACBAQAMAAcJkxOFfACBAQAAAA==.',
Ug='Ugotgotpal:BAAALgAECgcJCAAAAA==.',
Ul='Ulazain:BAABLgAECn8vAAIDAAkJDx90CQCJAgADAAkJDx90CQCJAgAAAA==.',
Ur='Urza:BAAALgADCgYJEwAAAA==.',
Us='Usdaprime:BAABLgAECn8fAAIhAAkJEA7FCgCzAQAhAAkJEA7FCgCzAQAAAA==.',
Va='Valarjar:BAAALgADCgIJAgABLgAECgYJBgAHAAAAAA==.Vandene:BAAALgAECgEJAQAAAA==.',
Ve='Velderen:BAAALgAECgQJBAAAAA==.Vengance:BAAALgADCgMJAwAAAA==.Verstappen:BAAALgADCgEJAQAAAA==.',
Vi='Viì:BAABLgAECn8YAAIMAAcJXgjssQAgAQAMAAcJXgjssQAgAQAAAA==.',
Vo='Volsunga:BAAALgAECgQJCgAAAA==.',
Vy='Vyndori:BAAALgAECgUJBQAAAA==.',
Wi='Wildling:BAAALgADCgMJAwAAAA==.Winda:BAAALgADCggJCQAAAA==.',
Wr='Wrease:BAAALgADCgQJBQAAAA==.',
Xa='Xam:BAAALgAECgYJEgAAAA==.Xaphyre:BAAALgADCgEJAQAAAA==.Xarthas:BAAALgAECgMJBAAAAA==.Xavia:BAABLgAECn8gAAIIAAgJaha6MgDQAQAIAAgJaha6MgDQAQAAAA==.',
Xy='Xylazel:BAABLgAECn8oAAIKAAkJbBb7JgAhAgAKAAkJbBb7JgAhAgAAAA==.',
Ya='Yasmina:BAAALgAECgYJDgAAAA==.',
Yv='Yvana:BAABLgAECn8YAAISAAUJGxyWKgBtAQASAAUJGxyWKgBtAQAAAA==.',
Za='Zaradrela:BAAALgAECgEJAQAAAA==.',
Zu='Zugmaster:BAAALgADCgEJAQAAAA==.',
Zz='Zzephyrdruid:BAACLgAFFH8eAAIjAAcJtSLjAACAAgAjAAcJtSLjAACAAgAuAAQKfx0AAiMACAnEJZcNAMECACMACAnEJZcNAMECAAAA.Zzephyrev:BAAALgAECgYJDwABLgAFFAcJHgAjALUiAA==.Zzephyrmage:BAAALgAFFAEJAgABLgAFFAcJHgAjALUiAA==.',
['Âs']='Âsunâ:BAABLgAECn8cAAIdAAgJORx+FABhAgAdAAgJORx+FABhAgAAAA==.',
['Ôä']='Ôäk:BAAALgADCgYJCwABLgAECgcJIQAdADYQAA==.',
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
