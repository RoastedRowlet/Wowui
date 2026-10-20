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

local lookup = {'Druid-Restoration','Shaman-Elemental','Druid-Balance','Paladin-Protection','Paladin-Retribution','Unknown-Unknown','Priest-Shadow','Mage-Arcane','Paladin-Holy','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Havoc','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Monk-Mistweaver','Priest-Holy','Warlock-Destruction','DemonHunter-Devourer','Warrior-Arms','DemonHunter-Vengeance','Hunter-Survival','Druid-Guardian','Shaman-Restoration','Warrior-Protection','Warrior-Fury','Priest-Discipline','Monk-Windwalker','Evoker-Preservation','Hunter-Marksmanship','Druid-Feral','Evoker-Augmentation','Monk-Brewmaster',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Aberforthd:BAAANQAECgQICQAAAA==.',
Ac='Aceforlife:BAAANQADCggIEQABNQAECgcIKgABAJsOAA==.Acorn:BAABNQAECn8oAAICAAoKARzWHwANAwACAAoKARzWHwANAwAAAA==.',
Ad='Aditu:BAABNQAECn8dAAMBAAcK/RWmNQBuAQABAAYKEhSmNQBuAQADAAcK5A0XLQCtAAAAAA==.',
Ae='Aetheris:BAABNQAECn8VAAIEAAgKNhXYLAB2AQAEAAgKNhXYLAB2AQAAAA==.',
Ag='Agasonex:BAAANQADCgUIBAAAAA==.',
Ah='Ahziz:BAAANQAECgYIEQAAAA==.',
Ai='Airent:BAAANQAECgYIDgAAAA==.',
Al='Alaestel:BAABNQAECn8tAAIFAAoKngtAogDcAQAFAAoKngtAogDcAQAAAA==.Aletheia:BAAANQAECgQIBAAAAA==.Alt:BAAANQAECgIIBAAAAA==.',
An='Ancane:BAAANQADCggICAAAAA==.Andramealoch:BAAANQADCgEIAQAAAA==.Angina:BAAANQADCgUIBwAAAA==.Angrywoogie:BAAANQADCgEIAQABNQAECgQIBwAGAAAAAA==.Annarcis:BAAANQAECgYICgAAAA==.Antiman:BAAANQAECgMIBgAAAA==.Anäster:BAABNQAECn8hAAIHAAgKdhblJAAJAgAHAAgKdhblJAAJAgAAAA==.',
Ao='Aoiris:BAAANQADCggIEAAAAA==.',
Ap='Aplcyder:BAABNQAECn8kAAIBAAoKDAt3EwAoAQABAAoKDAt3EwAoAQAAAA==.Apocryphea:BAAANQAECgQIBAAAAA==.',
Ar='Arachnid:BAABNQAECn8VAAIIAAQK2R/5ZwDtAAAIAAQK2R/5ZwDtAAAAAA==.Aradalon:BAABNQAECn8oAAIJAAkKmyFNDwBRAwAJAAkKmyFNDwBRAwAAAA==.Aratyn:BAABNQAECn8YAAIKAAcKshRpDQDaAQAKAAcKshRpDQDaAQAAAA==.',
As='Astranacht:BAABNQAECn8qAAIDAAgKTQ8tQwDoAQADAAgKTQ8tQwDoAQAAAA==.',
Au='Auntjemimma:BAABNQAECn8fAAIFAAgKyRIiiQAUAgAFAAgKyRIiiQAUAgAAAA==.Auriandra:BAAANQAECgQIBgAAAA==.',
Ax='Axa:BAAANQADCggIFAAAAA==.',
Ba='Babyshoes:BAAANQAECgQIBgAAAA==.Backhawk:BAAANQAECgQIBAAAAA==.Backsurgery:BAABNQAECn8ZAAQLAAgKbR9YBgDQAQALAAgKbR9YBgDQAQAMAAIKhRaUiACQAAANAAIKEhKMFgB/AAABNQAFFAUIDwAOABwdAA==.Baerrn:BAABNQAECn8VAAIPAAYKCwP4aQDRAAAPAAYKCwP4aQDRAAAAAA==.Baricia:BAABNQAECn8nAAIIAAoKpQvHZwDtAAAIAAoKpQvHZwDtAAAAAA==.Barrin:BAABNQAECn8dAAMQAAgKSRjmBwAYAgAQAAgKSRjmBwAYAgARAAIKSwCkQQE0AAAAAA==.Bastim:BAAANQADCgEIAgAAAA==.Bawnchu:BAAANQADCgcIFgAAAA==.',
Be='Beardad:BAAANQADCgcICQAAAA==.Bearded:BAAANQAECgYIDQAAAA==.Beastmaster:BAABNQAECn8iAAISAAoKNxtdDAAPAgASAAoKNxtdDAAPAgAAAA==.Beefcakell:BAAANQADCgQIBQAAAA==.Belthar:BAAANQAECgUIBQAAAA==.Bentlymage:BAABNQAECn8oAAIIAAoKvBvfVwDQAgAIAAoKvBvfVwDQAgAAAA==.',
Bi='Bissafiyah:BAACNQAFFH8bAAIOAAcKQh43AADKAgAOAAcKQh43AADKAgA1AAQKfzIAAg4ACgpCI4wCABECAA4ACgpCI4wCABECAAAA.Bittertea:BAAANQAECgYIEQAAAA==.',
Bl='Blakdeath:BAABNQAECn8ZAAITAAcKlwwQUQBuAQATAAcKlwwQUQBuAQAAAA==.Blargghh:BAAANQAECgYIBgAAAA==.Bloodgon:BAABNQAECn8aAAMUAAcKEBYqEABcAQAUAAcKEBYqEABcAQAVAAIKTA0mtABhAAAAAA==.Bloodpriests:BAAANQAECgYICAAAAA==.',
Bo='Bobthedemon:BAAANQAECgIIAwAAAA==.Bohica:BAAANQAECgQIBgAAAA==.Boka:BAAANQADCgMIAgAAAA==.Bonechop:BAAANQADCgIIAgAAAA==.Bowseye:BAAANQAECgIIAgABNQAECggIHwAFAMkSAA==.Boyakasha:BAAANQAECgUIDgAAAA==.',
Br='Brayne:BAAANQAECgYICwAAAA==.Brewsome:BAABNQAECn8vAAIWAAoKoSEjBQBQAwAWAAoKoSEjBQBQAwAAAA==.Brighthammer:BAAANQADCgcIDQAAAA==.Bryybryy:BAABNQAECn8qAAIVAAkKNhtzJgCKAgAVAAkKNhtzJgCKAgAAAA==.Bryyguyy:BAAANQADCgIIAgABNQAECgkJKgAVADYbAA==.',
Bu='Bubleherth:BAAANQADCgcIFwAAAA==.Bullymayes:BAAANQADCgEIAQAAAA==.Bunkiee:BAAANQADCggIFgAAAA==.',
Ca='Calbee:BAAANQADCgYIBQAAAA==.Candorite:BAAANQAECgUJBwABNQAECgcIEwAGAAAAAA==.Candra:BAAANQAECgEIAQAAAA==.Capcoms:BAAANQAECgUIDAABNQAECgkJLgAIAL0dAA==.Capita:BAABNQAECn8lAAIKAAcKbw+VEQCNAQAKAAcKbw+VEQCNAQAAAA==.Carsinegan:BAAANQAECgUIEAAAAA==.Cassica:BAABNQAECn8cAAMHAAgKDRI+MQCZAQAHAAcK4hE+MQCZAQAXAAYKeBMFkQBjAQAAAA==.Catskin:BAAANQADCgYICQAAAA==.Causticminx:BAAANQADCgEIAQAAAA==.',
Ch='Chainlink:BAAANQADCgIIAgAAAA==.Charkle:BAABNQAECn8ZAAISAAUKXQrlAAEDAQASAAUKXQrlAAEDAQAAAA==.Chillylilly:BAAANQAECggIEAAAAA==.Chummie:BAABNQAECn8oAAQRAAkKPR6jGACQAQARAAgKehyjGACQAQAQAAIKbSI6BwC/AAAYAAIK0xXkUACMAAAAAA==.Chuud:BAAANQADCgQIBAAAAA==.',
Ci='Ciandoril:BAAANQAECgQICgAAAA==.Cid:BAAANQADCgQIBAAAAA==.',
Co='Comeanddie:BAAANQADCggIFAABNQADCgMIAwAGAAAAAA==.Cow:BAAANQADCgEIAQAAAA==.',
Cr='Crazyeyes:BAAANQAECgQICAABNQAECggIGAADAAIJAA==.Crimsondeath:BAAANQAECgYIDgAAAA==.Crylecks:BAAANQAECgYIBgAAAA==.',
Cy='Cyclonian:BAAANQAECggICAABNQAECggIDQAGAAAAAA==.Cylu:BAAANQADCggIDAAAAA==.Cyprus:BAABNQAECn8ZAAMBAAoKlhMXCAC7AQABAAoKlhMXCAC7AQADAAEKAACctAAuAAAAAA==.',
Da='Daelric:BAAANQAECgEIAQAAAA==.Daender:BAABNQAECn8vAAISAAkK/yD0GgAtAwASAAkK/yD0GgAtAwAAAA==.Daenor:BAAANQAECgQIBAAAAA==.Daevie:BAABNQAECn8jAAIIAAkKxgXhfQDEAAAIAAkKxgXhfQDEAAAAAA==.Dairydemon:BAABNQAECn8pAAIZAAoKCQM1QQBEAQAZAAoKCQM1QQBEAQAAAA==.Damageus:BAABNQAECn8yAAMIAAoKbh/gGQCoAQAIAAkKqB7gGQCoAQAKAAIKfyQKEwBrAAAAAA==.Damworg:BAAANQAECgYIDQAAAA==.Daniryl:BAEANQAECgcIDwABNQAECgkJHgACAH0TAA==.Dar:BAABNQAECn8sAAISAAoK/Q/OcwApAgASAAoK/Q/OcwApAgAAAA==.Darcside:BAAANQAECgYIDQAAAA==.Daritar:BAEBNQAECn8eAAICAAkKfRPFLQAGAQACAAkKfRPFLQAGAQAAAA==.Darkburtus:BAABNQAECn8ZAAIZAAcKhQTtSgABAQAZAAcKhQTtSgABAQAAAA==.Darkfeatherr:BAAANQAECgIIBAAAAA==.Darkxwraith:BAABNQAECn8nAAMEAAgKBBcCEAATAQAEAAcKnRkCEAATAQAFAAEKCAoFpQE1AAAAAA==.Datsombeech:BAABNQAECn8nAAIaAAkKzwehvQCDAQAaAAkKzwehvQCDAQAAAA==.',
De='Defhammer:BAAANQADCgEIAQAAAA==.Deka:BAAANQADCgMIAwAAAA==.Deridex:BAAANQADCgEIAQAAAA==.Deàdly:BAAANQADCgUJDQAAAA==.',
Dh='Dhaynk:BAABNQAECn85AAMbAAoKtBnmAgCSAQAbAAcKryDmAgCSAQAZAAoKPxEoCwBiAQAAAA==.',
Di='Dianoia:BAAANQAECgQIBwABNQAFFAYIGQAYABcZAA==.Didamus:BAAANQADCgEIAQAAAA==.Dingleding:BAAANQAECgcICAAAAA==.',
Dk='Dkanabiss:BAAANQADCgYIEAAAAA==.Dkinabox:BAAANQADCgYIBwAAAA==.',
Do='Docoo:BAABNQAECn8iAAIVAAgKpCTmFgD2AgAVAAgKpCTmFgD2AgAAAA==.Dogmeat:BAAANQADCgEIAQAAAA==.Dominates:BAAANQAECgQIBAAAAA==.',
Dr='Dreu:BAAANQADCgUIBwABNQAFFAUIEwAZAI8WAA==.Drewserk:BAABNQAECn8sAAIaAAoKNhKJEQDLAQAaAAoKNhKJEQDLAQAAAA==.Driten:BAABNQAECn8uAAIIAAkKvR1rZQCzAgAIAAkKvR1rZQCzAgAAAA==.Drocsid:BAAANQAECggIDwABNQAECgoKMAAFAIchAA==.Drpiscisphd:BAAANQAECgEIAgABNQAECgoKMwAMAMohAA==.Drsaltyballz:BAAANQAECgIJAgAAAA==.Drspoon:BAABNQAECn8mAAIVAAoKRBTLFwArAQAVAAoKRBTLFwArAQAAAA==.Drugpala:BAAANQAECgEJAwAAAA==.Drumuss:BAAANQAECgMIBQAAAA==.',
Ds='Dsancho:BAAANQAECgYIDAAAAA==.',
Du='Ducat:BAAANQAECgYICgAAAA==.Dudley:BAAANQAECgMIBAAAAA==.Duffun:BAABNQAECn8ZAAIIAAcKmBqemgBLAgAIAAcKmBqemgBLAgABNQAECgoKNAAcANYjAA==.Duffunha:BAABNQAECn80AAIcAAoK1iMNAABVAwAcAAoK1iMNAABVAwAAAA==.',
Dy='Dyre:BAAANQAECgMIBgAAAA==.Dyslexic:BAAANQAECgQICgABNQAFFAIICAAFAK4KAA==.Dyspepsia:BAACNQAFFH8IAAIFAAIKrgqAKACCAAAFAAIKrgqAKACCAAA1AAQKfxsAAgUACQo/Fa6FABwCAAUACQo/Fa6FABwCAAAA.',
['Dõ']='Dõngus:BAAANQADCgYIBgABNQAECggIDQAGAAAAAA==.',
Ed='Edelgard:BAAANQAECgEIAgAAAA==.Edie:BAAANQAECgEIAQAAAA==.',
Ei='Eirenn:BAAANQAECggICAAAAA==.',
El='Eleaornu:BAABNQAECn8pAAIJAAkKFR2xBgBfAgAJAAkKFR2xBgBfAgAAAA==.Elimee:BAABNQAECn84AAIIAAoKPyFrHQBiAwAIAAoKPyFrHQBiAwAAAA==.Ellasia:BAAANQADCgEIAQAAAA==.Elvenbane:BAAANQAECgYIEQAAAA==.',
Em='Emart:BAAANQAECgMIBgAAAA==.',
Er='Erayna:BAABNQAECn8jAAIBAAgKDg3HLwCcAQABAAgKDg3HLwCcAQAAAA==.',
Es='Essence:BAABNQAECn8XAAIIAAoKpA8zoABBAgAIAAoKpA8zoABBAgAAAA==.',
Et='Etherious:BAAANQADCgUICwABNQADCggIDAAGAAAAAA==.',
Ev='Evehunter:BAAANQAECggIAQAAAA==.Evelenicus:BAAANQADCgEIAQAAAA==.Evelinah:BAAANQAECggICQAAAA==.Evïe:BAAANQAECgEIAgABNQAECgoKOAAIAD8hAA==.',
Fa='Falconclaw:BAAANQADCggIIQAAAA==.Falkensnoman:BAAANQAECgMIBgAAAA==.Fayedra:BAABNQAECn8aAAIdAAcKWRScHQCzAQAdAAcKWRScHQCzAQAAAA==.',
Fe='Feenii:BAABNQAECn8rAAIOAAoKXw5SAwDsAQAOAAoKXw5SAwDsAQAAAA==.',
Fi='Fizzlelich:BAAANQADCggIKwAAAA==.',
Fo='Foxdeer:BAABNQAECn8VAAIRAAcK4AgHZgC2AAARAAcK4AgHZgC2AAAAAA==.Foxxmccloud:BAAANQADCgIJAwABNQAECgoKJwADAKQfAA==.',
Fu='Fungies:BAABNQAECn8wAAIRAAoKLBJeXABCAgARAAoKLBJeXABCAgAAAA==.Furybest:BAAANQAECgQIBAAAAA==.Furyrage:BAAANQADCgQIBAAAAA==.',
Ga='Gannir:BAAANQAECgEIAQAAAA==.Gatlokal:BAAANQADCggIAgAAAA==.Gatman:BAAANQADCgYICQAAAA==.',
Gi='Gimiltockel:BAAANQADCgMIBAAAAA==.Giramar:BAAANQAECgYIDAAAAA==.',
Go='Gochujang:BAAANQAECgQIBAABNQAECgoKKAACAAEcAA==.Gojo:BAEANQAECgEIAwAAAA==.Goldeelock:BAAANQADCggIDgAAAA==.Gotchya:BAAANQADCgEIAQAAAA==.Goteem:BAAANQAECgUIBwAAAA==.Gothitelle:BAAANQADCgIIAgAAAA==.',
Gr='Grandad:BAAANQAECgQIBwAAAA==.Grandest:BAAANQADCgQIBQAAAA==.Grantaire:BAAANQADCggIFgAAAA==.Grimmdogg:BAAANQAECgMIAwAAAA==.Grimrox:BAABNQAECn8WAAICAAgK9BHScQDLAQACAAgK9BHScQDLAQAAAA==.Grombo:BAAANQAECgQIBgAAAA==.',
Gu='Guzstaff:BAAANQADCgEIAQABNQAECgUIGQASAF0KAA==.',
Ha='Haanit:BAAANQADCgIIAwAAAA==.Hakela:BAAANQAECgEJAQAAAA==.Hardlyevoker:BAAANQADCgMIAwABNQAECgkJMQAJAD8fAA==.',
He='Healingwave:BAAANQADCgYIBgAAAA==.Hearnê:BAAANQADCgIIAgAAAA==.Heavyarm:BAAANQADCgEIAQAAAA==.Heethen:BAAANQAECgUICQAAAA==.Hexbox:BAABNQAECn8ZAAMeAAgKLBefcAC6AQAeAAcK6xmfcAC6AQACAAcKHg8xhwCSAQAAAA==.',
Hi='Himawari:BAABNQAECn8hAAQfAAgKYRDoHQBmAQAfAAcKYRDoHQBmAQAaAAIKIwemwgA4AAAgAAEKAABKMwA1AAAAAA==.',
Ho='Hoffmin:BAABNQAECn8tAAMZAAoKORtPDgAEAwAZAAkKYh1PDgAEAwAPAAEKGgyckQA3AAAAAA==.Holemeister:BAABNQAECn8wAAIFAAoKPyLpDQAPAgAFAAoKPyLpDQAPAgAAAA==.Holyamin:BAAANQAECgMIBgAAAA==.Holymann:BAAANQAECgQICgAAAA==.Holyschnikey:BAABNQAECn8nAAIJAAcKzxXZHQB0AQAJAAcKzxXZHQB0AQAAAA==.Holyz:BAABNQAECn8cAAIJAAgKYSNrIgDjAgAJAAgKYSNrIgDjAgAAAA==.Horgable:BAAANQADCgEIAQAAAA==.Horrorpops:BAAANQAECgYIBwABNQAECgkJLwASAP8gAA==.',
Hu='Hugginz:BAAANQADCgYIEgAAAA==.Hunzul:BAAANQADCgQIBQAAAA==.',
Hy='Hypnototem:BAAANQAECgEIAQAAAA==.',
['Hè']='Hèimdall:BAABNQAECn8XAAIEAAYKuQrDSADKAAAEAAYKuQrDSADKAAAAAA==.',
['Hí']='Hílthaen:BAABNQAECn8nAAIXAAkKjR73LgCsAgAXAAkKjR73LgCsAgAAAA==.',
Ic='Icehead:BAAANQAECgQIAwAAAA==.Ichigokisu:BAAANQADCgQIBQAAAA==.',
Ih='Ihavenobrain:BAAANQADCgEIAQAAAA==.',
Il='Illy:BAABNQAECn8dAAIZAAgKTxCMKgDtAQAZAAgKTxCMKgDtAQAAAA==.',
In='Instantdeath:BAAANQADCgMIAwAAAA==.',
Is='Ishivyounot:BAAANQADCgUICgAAAA==.',
Iv='Ivranda:BAAANQAECgcIEwAAAA==.',
Ix='Ixio:BAAANQADCgYIBgAAAA==.',
Ja='Jahan:BAABNQAECn8sAAMXAAoK/iOyBwCHAwAXAAoKqSKyBwCHAwAhAAcKXR7vBABtAgABNQAECgQIBAAGAAAAAA==.Jamie:BAABNQAECn8VAAMVAAcKgSSLKQB2AgAVAAYKgSSLKQB2AgAUAAEKAADP4AAzAAABNQAFFAcIDgARAAgjAA==.Jarek:BAAANQADCgEIAQAAAA==.Jaspe:BAAANQADCgEIAQAAAA==.',
Je='Jegra:BAABNQAECn8hAAIiAAgKVR5bGgBtAgAiAAgKVR5bGgBtAgAAAA==.Jerith:BAABNQAECn8sAAMMAAkKUwzcBQC+AQAMAAkKUwzcBQC+AQALAAYKPwWqNAAVAQAAAA==.Jerryy:BAEANQADCgEIAgABNQAECgEIAwAGAAAAAA==.Jessilyn:BAAANQADCggIFQAAAA==.',
Ji='Jiffjr:BAAANQADCgEIAQAAAA==.Jigari:BAAANQADCgcIEAAAAA==.Jinxed:BAAANQAECgMIAwAAAA==.',
Jo='Jord:BAAANQAECgQIBAAAAA==.',
Ju='Jubellina:BAABNQAECn8yAAIWAAoKQA+kCwAbAQAWAAoKQA+kCwAbAQAAAA==.Jubîlee:BAAANQADCgEIAQAAAA==.',
['Jà']='Jàzz:BAAANQADCgYIIAAAAA==.',
Ka='Kaelora:BAAANQADCgYICQAAAA==.Kaerei:BAAANQADCgQJBAAAAA==.Kaleb:BAECNQAFFH8MAAIPAAUKghZFDQA7AQAPAAUKghZFDQA7AQA1AAQKfzMAAg8ACgrxIbYGAIsDAA8ACgrxIbYGAIsDAAAA.Kalferno:BAAANQAECgIIAgAAAA==.Kalirkaz:BAAANQAECgQIBQABNQAECgoKJAAeAJEdAA==.Kayotica:BAAANQAECgMIAwAAAA==.',
Ke='Kendall:BAAANQAECgQIBAABNQAECgcIFAATANMNAA==.',
Kh='Khallock:BAAANQAECgQIDwAAAA==.',
Ki='Kiemen:BAABNQAECn8UAAMTAAcK0w1FTACHAQATAAcK0w1FTACHAQAUAAYK7ApShAAOAQAAAA==.Killko:BAABNQAECn8bAAMTAAgK6RBuRACwAQATAAgK6RBuRACwAQAUAAIKpQrVyABaAAAAAA==.Kirisen:BAAANQAECgIIAwAAAA==.',
Kn='Knardan:BAABNQAECn8kAAISAAkKqhruIwCJAQASAAkKqhruIwCJAQAAAA==.',
Ko='Kotanx:BAAANQADCggIEQAAAA==.',
Kr='Kragsloor:BAAANQADCggICwAAAA==.',
Ku='Kuraki:BAABNQAECn8aAAIiAAcKIAsfOABTAQAiAAcKIAsfOABTAQAAAA==.',
Ky='Kylandria:BAAANQADCgEIAQAAAA==.Kyriea:BAAANQADCgYIBwAAAA==.',
La='Ladrar:BAAANQAECgEIAQAAAA==.Lanadiel:BAABNQAECn8sAAIEAAkKFSJlCgD0AgAEAAkKFSJlCgD0AgAAAA==.Lasalghoul:BAAANQAECggIDgAAAA==.Lassyn:BAAANQAECggICQABNQAECggIDgAGAAAAAA==.',
Le='Legend:BAABNQAECn8VAAIVAAgK2BUzUgCsAQAVAAgK2BUzUgCsAQAAAA==.Len:BAABNQAECn8rAAMeAAkKeBLCWQADAgAeAAkKeBLCWQADAgACAAUKbwx8yAABAQAAAA==.Leoñidas:BAAANQAECgUICwAAAA==.',
Li='Lian:BAAANQAECgQIBQAAAA==.Lianda:BAAANQAECggICAAAAA==.Lianse:BAAANQADCgYIDQAAAA==.Liliara:BAABNQAECn8oAAISAAoKNxTHKQB0AQASAAoKNxTHKQB0AQAAAA==.Lillyirl:BAAANQADCgcIBwAAAA==.Lillymae:BAABNQAECn8XAAIZAAkKtx8JAgBUAgAZAAkKtx8JAgBUAgAAAA==.Lillyslight:BAAANQADCgUIBQAAAA==.Lillytae:BAAANQADCgYIBgAAAA==.Lillyvani:BAAANQADCgcIBwAAAA==.Lilmoo:BAAANQAECgYIDQAAAA==.Lilpump:BAAANQAECgQICQABNQAECgoKJgAVAEQUAA==.Lindalinda:BAAANQADCgEIAQAAAA==.Linkhunter:BAAANQAECgUICwABNQAECgoKKgAhAMoeAA==.Linkmônk:BAAANQADCgcICwABNQAECgoKKgAhAMoeAA==.',
Lo='Lodise:BAABNQAECn8mAAIQAAcKNhL+AgBCAQAQAAcKNhL+AgBCAQAAAA==.Lorzz:BAABNQAECn8vAAIXAAoK+hx7JADaAgAXAAoK+hx7JADaAgAAAA==.Loveydovey:BAAANQADCgIIBQAAAA==.',
Lu='Lucrio:BAABNQAECn8rAAIUAAkKXhSBGAAfAQAUAAkKXhSBGAAfAQAAAA==.Ludlow:BAAANQADCgMIBAABNQAECgkJJQAMAJUQAA==.Lunalai:BAAANQAECgQIBAAAAA==.Lurim:BAABNQAECn8oAAIdAAoKhB8PBgAzAwAdAAoKhB8PBgAzAwAAAA==.Lushy:BAABNQAECn8tAAILAAgKjxO4CACmAQALAAgKjxO4CACmAQAAAA==.',
Ly='Lylindara:BAABNQAECn8ZAAIeAAgKJgjDkwBWAQAeAAgKJgjDkwBWAQAAAA==.Lylinette:BAAANQADCggIEAAAAA==.',
['Ló']='Lókï:BAAANQADCgEIAQAAAA==.',
Ma='Madgorilla:BAAANQADCgUIBQAAAA==.Mageofdeath:BAABNQAECn8lAAMKAAcKTQ0yCQD4AAAIAAYKhAmvKQFGAQAKAAUKxA4yCQD4AAABNQADCgMIAwAGAAAAAA==.Mageskin:BAAANQAECgMIBwAAAA==.Maladaptive:BAAANQADCgYIDwAAAA==.Manerva:BAAANQADCgcIIAAAAA==.Mastorcheef:BAAANQADCgQIBAAAAA==.Maurin:BAAANQAECgMIAwAAAA==.Maximumhonk:BAABNQAECn8lAAIeAAcKchxYHgBxAQAeAAcKchxYHgBxAQAAAA==.Maxonoa:BAAANQADCggJFwAAAA==.Maxximos:BAAANQADCgYICQAAAA==.',
Mc='Mcstabbystab:BAAANQADCgEIAgAAAA==.',
Me='Mekkadaddy:BAABNQAECn8aAAISAAcKCBLGpQC6AQASAAcKCBLGpQC6AQAAAA==.Mellow:BAAANQAECgMIAwAAAA==.Mendelia:BAABNQAECn8dAAIEAAcKVBbCJgCoAQAEAAcKVBbCJgCoAQAAAA==.Mercus:BAABNQAECn8hAAMLAAgKyA9aIgC4AQALAAcKVg9aIgC4AQAMAAcKvA43RwCoAQAAAA==.Merllinna:BAAANQADCgEIAQAAAA==.Mervenious:BAAANQAECgQIEAAAAA==.Mesowasted:BAAANQADCgEIAQAAAA==.',
Mi='Milkmaiden:BAAANQADCgEIAQAAAA==.Mindplague:BAABNQAECn8jAAIHAAYKqRxoJQAEAgAHAAYKqRxoJQAEAgAAAA==.Minipincin:BAAANQAECgMIAwAAAA==.Minmzey:BAAANQAECgIJAgAAAA==.Miroslava:BAAANQAECgUIBQAAAA==.Missfire:BAAANQAECgcIEgABNQAECgoKGQABAJYTAA==.',
Mk='Mkaye:BAAANQAECgIIAgAAAA==.',
Mo='Moggle:BAAANQAECgYIEQAAAA==.Mondazi:BAABNQAECn8wAAMCAAoKehp+OQCQAgACAAkK3Bh+OQCQAgAeAAkKlA7NaADSAQAAAA==.Moonlilly:BAAANQADCgIIAgAAAA==.Morfy:BAAANQADCgEIAwAAAA==.Morgzim:BAAANQADCgYJBwAAAA==.Moustaccio:BAAANQAECgEIAgAAAA==.Mozarta:BAAANQADCgEIAQAAAA==.',
Ms='Msmanalow:BAAANQAECgEIAQABNQAECgoKGQABAJYTAA==.',
My='Mycen:BAABNQAECn8XAAIRAAgKbgw7kQC7AQARAAgKbgw7kQC7AQAAAA==.Myeyesburn:BAAANQAECgMJBAAAAA==.Myxo:BAAANQADCgEIAQAAAA==.',
['Má']='Málaketh:BAAANQAECgYIBgAAAA==.',
Na='Nardena:BAAANQAECgEIAQAAAA==.Narz:BAABNQAECn80AAISAAoKAQtQPAA/AQASAAoKAQtQPAA/AQAAAA==.Naughtypine:BAAANQADCgYIBgAAAA==.Naylz:BAAANQAECggIAQAAAA==.',
Ne='Necronomikon:BAABNQAECn8UAAIIAAcK3Azq9ACiAQAIAAcK3Azq9ACiAQAAAA==.Nerhzul:BAAANQADCgUIBQAAAA==.Neromoo:BAAANQAECgUIDQABNQAECgoKFgAjADgNAA==.Neruphuyt:BAABNQAECn8YAAIDAAgKAgnkXABdAQADAAgKAgnkXABdAQAAAA==.',
Ni='Niath:BAAANQAECgUICQAAAA==.Nightheal:BAAANQADCgEIAQABNQAECggIIgAVAKQkAA==.Nightsniper:BAAANQAECgEIAQABNQAECggIIgAVAKQkAA==.',
No='Notdinor:BAAANQADCgIIAwAAAA==.Notlilly:BAABNQAECn8lAAIfAAkKFhE2BgBaAQAfAAkKFhE2BgBaAQAAAA==.Notpillows:BAAANQAECgEIAQAAAA==.',
Ny='Nyxelle:BAAANQAECgIIAwAAAA==.',
['Nä']='Närz:BAAANQADCggIBQAAAA==.',
['Nò']='Nòvà:BAAANQAECgQICgAAAA==.',
Oi='Oilfu:BAAANQADCgUIBQABNQAECggILQALAI8TAA==.',
Ok='Okioni:BAAANQAECgUIBQAAAA==.',
Ol='Olgon:BAABNQAECn8rAAISAAkKuBCkVgBuAgASAAkKuBCkVgBuAgAAAA==.',
Op='Oprhawinfury:BAABNQAECn8fAAIUAAgKHwteJQDRAAAUAAgKHwteJQDRAAAAAA==.',
Or='Orgodemir:BAABNQAECn8aAAIXAAcKByWTIADtAgAXAAcKByWTIADtAgAAAA==.Orhamin:BAAANQADCgYIEAAAAA==.',
Os='Oshani:BAAANQAECgQIBAAAAA==.',
Ou='Outlaw:BAAANQADCgcIBwAAAA==.',
Pa='Pacolyte:BAAANQAECgMIBAAAAA==.Paigor:BAAANQADCgEIAQAAAA==.Pakzakhan:BAAANQADCgEIAQAAAA==.Palathene:BAABNQAECn8VAAMFAAkKpxmbZwBlAgAFAAkKFhmbZwBlAgAEAAQKnR0wNABCAQAAAA==.Pallystorm:BAAANQAECgYICAAAAA==.Palmike:BAAANQADCgYIBgAAAA==.Pandemonia:BAABNQAECn8xAAIRAAkK/RC4dQABAgARAAkK/RC4dQABAgAAAA==.Parsie:BAAANQAECgIIAgAAAA==.Pathibas:BAAANQADCggIDgABNQAECgkJLgAgALkfAA==.Pattycakes:BAABNQAECn8mAAIUAAkKtw3WCQCbAQAUAAkKtw3WCQCbAQAAAA==.',
Ph='Pherocious:BAAANQAECgQIBgAAAA==.',
Pi='Pinktuesday:BAAANQADCggICgAAAA==.Pixeleen:BAACNQAFFH8FAAISAAQKrATjFQANAQASAAQKrATjFQANAQA1AAQKfzEAAxIACgqmIcwmAPwCABIACgqmIcwmAPwCACQABQrfCvJMAP4AAAAA.',
Pl='Plexy:BAABNQAECn8gAAMXAAkKYSDbIQDnAgAXAAkKuh/bIQDnAgAhAAcK8hlaCADhAQAAAA==.',
Po='Pogi:BAAANQADCgEIAQAAAA==.Pokitz:BAABNQAECn8VAAIFAAcKVAV9nQCiAAAFAAcKVAV9nQCiAAAAAA==.',
Pr='Primordinor:BAABNQAECn8oAAICAAcK3RqMHwA9AQACAAcK3RqMHwA9AQAAAA==.Probnotalive:BAABNQAECn8rAAISAAoKqRspFwA+AwASAAoKqRspFwA+AwAAAA==.Probnoturmom:BAABNQAECn8pAAIXAAkK4h3BFgC7AQAXAAkK4h3BFgC7AQAAAA==.',
Qu='Quacko:BAAANQAECgUIBQABNQAECgoKKAAdAIQfAA==.',
Ra='Raevyn:BAAANQAECgIIAgAAAA==.Raikai:BAAANQAECgEIAQABNQAECgkJKQAJABUdAA==.Rakan:BAABNQAECn8xAAMfAAoKehusBwDdAgAfAAoKehusBwDdAgAaAAUKeQ2M6AAUAQAAAA==.Rallick:BAABNQAECn8kAAIJAAoKbBFNVAAdAgAJAAoKbBFNVAAdAgAAAA==.Ranì:BAABNQAECn8vAAMfAAgKLBiSAwCqAQAfAAgKLBiSAwCqAQAgAAEKfAd+FwA1AAAAAA==.Rathger:BAAANQADCgUICgAAAA==.Ratmilk:BAAANQAECgcIDAAAAA==.Razkhan:BAAANQADCgcIDgAAAA==.',
Rd='Rdk:BAAANQAECgMIBAAAAA==.',
Re='Redek:BAAANQADCgcICgAAAA==.Reighna:BAAANQADCggIDgAAAA==.Rendwee:BAABNQAECn8xAAIlAAgK5h7mAQDvAQAlAAgK5h7mAQDvAQAAAA==.Reps:BAAANQAECggICwAAAA==.Retiredaggro:BAAANQAECgUIDgAAAA==.Retiredghoul:BAAANQADCgUIBQAAAA==.Retiredlight:BAAANQADCgEIAQAAAA==.Reuel:BAAANQADCgYIBgAAAA==.Rewolf:BAAANQAECgYIEAAAAA==.',
Rh='Rhaella:BAAANQAECgEIAQAAAA==.Rhynar:BAAANQAECggICAAAAA==.',
Ri='Ricflairion:BAABNQAECn8nAAImAAcKdQwFBQDeAAAmAAcKdQwFBQDeAAAAAA==.Rill:BAAANQADCggICwAAAA==.',
Ro='Rodcet:BAABNQAECn8wAAIFAAoKhyGdHgBJAwAFAAoKhyGdHgBJAwAAAA==.Roflbubble:BAABNQAECn8nAAMXAAkKnhRYYAAAAgAXAAkKnhRYYAAAAgAHAAUKdAWqVQC2AAAAAA==.Rognan:BAAANQADCgMIBQAAAA==.Roku:BAAANQAECgEIAQAAAA==.Ronkin:BAAANQADCgcIHgAAAA==.Rookgue:BAABNQAECn8uAAIMAAgKDxG/EQA2AQAMAAgKDxG/EQA2AQAAAA==.Rookoker:BAAANQAECgUIDgAAAA==.Rorygazer:BAAANQAECgYIEQAAAA==.Rosmerta:BAAANQADCgYICAAAAA==.Rossdair:BAAANQAECgUICgABNQAECgcICwAGAAAAAA==.Rossperot:BAABNQAECn8bAAIUAAcKLh10SgDsAQAUAAcKLh10SgDsAQAAAA==.',
Ry='Ryk:BAAANQAECgUIBgAAAA==.',
Sa='Saarin:BAAANQADCggIDAAAAA==.Saelara:BAAANQAECgUIBQAAAA==.Sairal:BAAANQAECggIEAAAAA==.Saltytuesday:BAAANQADCgYICgAAAA==.Samgee:BAACNQAFFH8QAAIFAAQKpw8CEQA+AQAFAAQKpw8CEQA+AQA1AAQKfzMAAgUACgqMHvQzAP0CAAUACgqMHvQzAP0CAAAA.Sawlty:BAABNQAECn8eAAIkAAgKrw4YMADNAQAkAAgKrw4YMADNAQAAAA==.Saynar:BAABNQAECn8mAAMZAAoKCR9uBwCYAQAZAAoKAB9uBwCYAQAbAAIKRR1VJgCHAAAAAA==.',
Sc='Scattered:BAABNQAECn8gAAMYAAgKVQ0MJwA+AQAYAAYKqQsMJwA+AQARAAUKqguWggB+AAAAAA==.Schecter:BAABNQAECn8YAAMeAAcKJyOUMQCaAgAeAAcKJyOUMQCaAgACAAEKCxj0KQE/AAAAAA==.Scintila:BAAANQADCgQIBAABNQAECgkJMQARAP0QAA==.Scooti:BAAANQADCggIEAABNQAECgYICgAGAAAAAA==.',
Se='Seba:BAABNQAECn9AAAIIAAoKTxq/FwCxAQAIAAoKTxq/FwCxAQAAAA==.Sebushko:BAAANQADCgEIAQABNQAECgoKQAAIAE8aAA==.Sehren:BAAANQADCgcIBgAAAA==.Sehtrak:BAAANQADCggICAAAAA==.Selesne:BAABNQAECn8aAAINAAcK/wkTDgBcAQANAAcK/wkTDgBcAQAAAA==.Seniandrays:BAAANQADCgQIBAAAAA==.Serannia:BAAANQADCgIIAgAAAA==.Seraphicktwo:BAABNQAECn8YAAMHAAcKwgzpPQA9AQAHAAcKwgzpPQA9AQAXAAEKTgYI/gAvAAAAAA==.',
Sh='Shadowlune:BAAANQADCgEIAQAAAA==.Shadowtrance:BAAANQADCgcIDgABNQAECggIJwAEAAQXAA==.Shaggmz:BAAANQAECgYIDgAAAA==.Shawnkin:BAAANQADCgIIAgAAAA==.Shelyn:BAAANQAECgIIAgAAAA==.Shinma:BAAANQAECgUIDgAAAA==.Shootermcgee:BAAANQAECgIIAgAAAA==.Showtootsies:BAAANQADCgUJBQAAAA==.Shrubbery:BAAANQAECgQIBwAAAA==.Shymary:BAAANQAECgUIDgAAAA==.',
Si='Siete:BAAANQADCgYJBwAAAA==.Silëx:BAABNQAECn8YAAIKAAcKGBesDgC/AQAKAAcKGBesDgC/AQAAAA==.Sindiz:BAAANQAECgQIDAAAAA==.Siouxiesioux:BAAANQAECgQIBAAAAA==.',
Sk='Skadie:BAAANQAECgIIAgAAAA==.Skoot:BAAANQAECgYICgAAAA==.Skullbender:BAAANQADCgEIAQAAAA==.',
Sl='Sliceamatic:BAAANQADCgEIAQAAAA==.Slimjimz:BAAANQADCgUIBQAAAA==.Slugondeez:BAABNQAECn8xAAMJAAkKPx9NJwDMAgAJAAkKPx9NJwDMAgAEAAIKUyMyTwCqAAAAAA==.',
Sm='Smitefist:BAAANQAECgEIAQABNQAECggIDQAGAAAAAA==.',
Sn='Snkyturtle:BAABNQAECn8vAAISAAkKKQ2ygQAJAgASAAkKKQ2ygQAJAgAAAA==.Snoopdogydog:BAAANQADCgEIAQAAAA==.Snuzzle:BAABNQAECn8kAAIdAAkKnhYYFAAjAgAdAAkKnhYYFAAjAgAAAA==.',
So='Sourmash:BAAANQAECgQIBAAAAA==.',
Sp='Spaghet:BAAANQAECgcIEwAAAA==.Spillthetea:BAAANQADCggICwABNQAECgYIEQAGAAAAAA==.Spittoon:BAAANQADCgEJAQABNQADCggIGAAGAAAAAA==.Sploot:BAABNQAECn8ZAAIRAAoKXhaMQQCNAgARAAoKXhaMQQCNAgAAAA==.',
Sr='Srasjet:BAAANQAECgQIBwAAAA==.',
Ss='Ssarmandok:BAAANQAECgcIEQAAAA==.',
St='Stabytha:BAAANQAECgYIDAAAAA==.Stark:BAAANQADCgEIAQAAAA==.Starlight:BAAANQAECggIEwAAAA==.Stealthed:BAAANQAECgQICwAAAA==.Stender:BAAANQADCgIIAgABNQAFFAIICQAPAH8eAA==.Stonegoddess:BAAANQADCgQIBQAAAA==.Stonesong:BAAANQADCgEIAQAAAA==.Stormcall:BAAANQAECgQICAAAAA==.Stratusfied:BAAANQADCgIIAwAAAA==.Strongmojo:BAAANQAECgEIAgAAAA==.Strongsad:BAAANQAECgEIAQAAAA==.',
Sw='Swiss:BAABNQAECn8aAAICAAcKHw90gACjAQACAAcKHw90gACjAQAAAA==.',
Sy='Syldra:BAAANQADCgEIAQAAAA==.',
['Sá']='Sáëgárón:BAAANQAECgMIBAAAAA==.',
Ta='Taliden:BAAANQAECgMIBQAAAA==.Tankinstine:BAAANQADCgYIBwAAAA==.Taraylda:BAAANQAECgYIEQAAAA==.Tarz:BAAANQAECgUIBQABNQAECgYIDQAGAAAAAA==.Tazzwolfsong:BAAANQADCgEIAQAAAA==.',
Te='Tecdor:BAAANQADCgYJBgAAAA==.Teronfiggy:BAAANQAECgYIDAAAAA==.',
Tf='Tfirs:BAAANQAECgQJBwABNQAFFAMIAwAGAAAAAA==.',
Th='Tharizdun:BAAANQADCgEIAQAAAA==.Thehealczar:BAAANQAECgcIDwABNQAECggIIgAVAKQkAA==.Theokoles:BAAANQAECggIDQAAAA==.Thesenate:BAAANQADCggIEAABNQAECgoKKwAOAF8OAA==.Thickblòód:BAAANQAECgIIAwAAAA==.Thordurin:BAAANQAECgYIBgAAAA==.Thorly:BAAANQADCgYIDQAAAA==.Thrazi:BAAANQAECgIIAgAAAA==.',
Ti='Tiadalma:BAAANQADCgEIAQAAAA==.Tinn:BAAANQADCggIEAAAAA==.',
To='Toospookie:BAAANQADCgYIDgAAAA==.Totem:BAAANQAECgQIBQAAAA==.',
Tr='Tramplip:BAABNQAECn8UAAIYAAUKbgtsCACYAAAYAAUKbgtsCACYAAAAAA==.Treecloud:BAABNQAECn8kAAIdAAgKMyFCCAD6AgAdAAgKMyFCCAD6AgAAAA==.Treferimore:BAAANQAECgUIDAAAAA==.Trevian:BAABNQAECn8aAAIFAAcKhQ7VxQCQAQAFAAcKhQ7VxQCQAQAAAA==.',
Tu='Tuluxxi:BAABNQAECn8tAAMeAAkKyiHlGgAEAwAeAAkKyiHlGgAEAwACAAgKfQ49dADEAQAAAA==.Tutter:BAAANQAECgUIBwAAAA==.',
Tw='Twopumpchump:BAABNQAECn8dAAInAAcKEBKCBwDtAAAnAAcKEBKCBwDtAAAAAA==.',
Tz='Tzxdh:BAAANQAECgIIAgABNQAECggIFQAEADYVAA==.Tzxdruid:BAAANQAECgIIAwABNQAECggIFQAEADYVAA==.',
Ug='Uglymancer:BAABNQAECn8cAAIRAAkK+BTqggDfAQARAAkK+BTqggDfAQAAAA==.',
Uj='Ujimas:BAABNQAECn8XAAICAAUKBhP+qwA7AQACAAUKBhP+qwA7AQAAAA==.',
Ut='Uthodne:BAAANQAECgEIAQABNQAECgkJJQAMAJUQAA==.',
Va='Vampireshade:BAABNQAECn8nAAMMAAkKxAoFPQDcAQAMAAkKxAoFPQDcAQANAAYK/gMzEgDlAAAAAA==.Vampirevoid:BAAANQADCgUIBQAAAA==.Vanililly:BAABNQAECn8oAAIVAAkKDA3UDQB3AQAVAAkKDA3UDQB3AQAAAA==.Vanimao:BAAANQAECgEIAQAAAA==.Varan:BAAANQAECgQIBAAAAA==.',
Vb='Vbull:BAAANQAECgEIAQAAAA==.',
Ve='Velissari:BAAANQAECgMICAAAAA==.Venano:BAAANQADCgEIAQAAAA==.Venatra:BAAANQADCgYICwAAAA==.Veritus:BAABNQAECn8oAAIPAAkKPR2NBAAfAgAPAAkKPR2NBAAfAgAAAA==.',
Vi='Vindict:BAAANQAECgMIBgAAAA==.Violette:BAABNQAECn8YAAISAAUKbhG7cwDFAAASAAUKbhG7cwDFAAAAAA==.Vion:BAAANQADCgEIAgAAAA==.',
Vo='Voidlink:BAABNQAECn8qAAIhAAoKyh7rAQAYAwAhAAoKyh7rAQAYAwAAAA==.Voidstriker:BAAANQAECgEIAQAAAA==.',
Vy='Vynboi:BAAANQADCgEIAQAAAA==.',
Wa='Wackyrellek:BAABNQAECn8YAAMMAAoK8RwlBADyAQAMAAkK8RwlBADyAQALAAIKVQIZSgBpAAAAAA==.Wakancer:BAABNQAECn8VAAIQAAUKQw8KEgAqAQAQAAUKQw8KEgAqAQAAAA==.Wakarisma:BAAANQAECgEIAQAAAA==.Wakataclysm:BAAANQAECgQICwAAAA==.Walnut:BAAANQAECgQIBAABNQAECgoKKAACAAEcAA==.Warchylde:BAAANQADCgUICgAAAA==.Warolderoy:BAABNQAECn8uAAMgAAkKuR8HBQDbAgAgAAkKUx8HBQDbAgAfAAYKkBqAFwC0AQAAAA==.',
We='Weedshaman:BAAANQADCgcJBwAAAA==.Weil:BAAANQAECgQIBQAAAA==.',
Wo='Woker:BAAANQAECgQIBAABNQAECgoKKwAOAF8OAA==.Woogie:BAAANQAECgQIBwAAAA==.Worthy:BAAANQAECgMIAwAAAA==.',
Wu='Wummie:BAAANQAECgMIAwABNQAECgkJKAARAD0eAA==.',
['Wò']='Wòógie:BAAANQADCgYIBgABNQAECgQIBwAGAAAAAA==.',
Xa='Xader:BAAANQADCggIEAAAAA==.',
Xe='Xenna:BAAANQAECgUICgABNQAECggIHwAFAMkSAA==.Xeq:BAAANQAECgMIAwAAAA==.',
Xi='Xiata:BAAANQAECgIIAgAAAA==.',
Xy='Xylanthia:BAAANQADCgEIAQAAAA==.',
Ye='Yeoman:BAABNQAECn8UAAIgAAYKHREiEwBvAQAgAAYKHREiEwBvAQAAAA==.Yewko:BAAANQAECgYIEwAAAA==.',
Yg='Yggdralith:BAAANQAECggIGgAAAQ==.',
Yo='Yobagoya:BAAANQAECgIIAQAAAA==.',
Yu='Yukionne:BAAANQAECgEIAQAAAA==.Yunohealme:BAABNQAECn8aAAITAAcK/Rn6MwAOAgATAAcK/Rn6MwAOAgAAAA==.Yunosmall:BAAANQADCgMIAwAAAA==.Yunosmart:BAAANQADCgMIBQAAAA==.',
['Yö']='Yör:BAAANQADCgEIAQAAAA==.',
Za='Zaen:BAABNQAECn8xAAMRAAoK/xueJADyAgARAAoK/xueJADyAgAYAAMK1BhSQADBAAAAAA==.Zandre:BAABNQAECn8iAAIfAAgKExemEwDrAQAfAAgKExemEwDrAQAAAA==.Zarkir:BAABNQAECn8sAAMVAAoKoyASDQBIAwAVAAoKoyASDQBIAwATAAEKwAlUYgBBAAAAAA==.',
Ze='Zelily:BAABNQAECn8pAAISAAkKSQyvhAACAgASAAkKSQyvhAACAgAAAA==.Zenarri:BAAANQADCgYICgAAAA==.',
Zh='Zharvakko:BAABNQAECn8lAAMCAAoKHRdlhACaAQACAAcKrhBlhACaAQAeAAoK3hSBJwBEAQABNQAECgoKJAAeAJEdAA==.Zhiana:BAABNQAECn8cAAMKAAgKQxFHDgDHAQAIAAgKOwxj3gDLAQAKAAgK7A1HDgDHAQAAAA==.',
Zo='Zornov:BAAANQADCgcICAABNQAECgoKKAAdAIQfAA==.',
Zu='Zulrich:BAAANQAECgYICwAAAA==.',
Zv='Zvirae:BAAANQADCggICAAAAA==.Zvirax:BAAANQADCgcIIwABNQADCggICAAGAAAAAA==.',
['Ás']='Ástrid:BAAANQAECgEIAQAAAA==.',
['Ëu']='Ëuni:BAAANQADCgQIBQAAAA==.',
['Ìs']='Ìsaac:BAAANQAECgYJEgAAAA==.',
['Ðo']='Ðolm:BAAANQAECgMIBAAAAA==.',
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
