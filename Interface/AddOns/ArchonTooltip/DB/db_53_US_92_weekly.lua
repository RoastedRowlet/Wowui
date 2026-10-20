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

local lookup = {'Mage-Arcane','Paladin-Retribution','Druid-Feral','Druid-Restoration','Unknown-Unknown','Druid-Balance','Rogue-Assassination','Shaman-Enhancement','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Warrior-Protection','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Priest-Holy','Druid-Guardian','DeathKnight-Unholy','Mage-Frost','Priest-Discipline','DeathKnight-Frost','Hunter-Marksmanship','Warlock-Affliction','Paladin-Holy','Monk-Mistweaver','DeathKnight-Blood','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw','Priest-Shadow',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abrakådabruh:BAABNQAECn8gAAIBAAcKKhLBygDwAQABAAcKKhLBygDwAQAAAA==.Absolverator:BAAANQADCgQIBAAAAA==.Abzero:BAAANQAECgIIAgAAAA==.',
Ac='Acnologia:BAAANQAECgQIBQAAAA==.',
Ae='Aeropos:BAAANQABCgEIAQAAAA==.',
Ah='Ahron:BAABNQAECn8dAAICAAoKhxKofAAxAgACAAoKhxKofAAxAgAAAA==.',
Ai='Ainjel:BAAANQAECgEIAQAAAA==.Ainz:BAAANQADCgYICgAAAA==.',
Ak='Akaitsuki:BAABNQAECn8kAAMDAAkKkRQ3DwAeAgADAAkKkRQ3DwAeAgAEAAQKzAEcZAB1AAAAAA==.',
Al='Alex:BAAANQADCggICAAAAA==.Alexdh:BAAANQADCgcIBwAAAA==.Alexr:BAAANQADCgUIBQABNQADCgcIBwAFAAAAAA==.Alexxh:BAAANQADCgMIAwABNQADCgcIBwAFAAAAAA==.Alisson:BAAANQADCgEIAQABNQADCgcIBwAFAAAAAA==.',
Am='Amarantus:BAAANQAECgcICAABNQAECgoKNAAGAAkbAA==.Amarndeus:BAAANQABCgcICQAAAA==.Ammerie:BAAANQADCgUJBQAAAA==.Ampkhwa:BAAANQADCggIBwAAAA==.',
An='Anmoa:BAABNQAECn8cAAIHAAgKphknCwB0AQAHAAgKphknCwB0AQABNQAFFAUIEgAIAC4cAA==.Anmodru:BAAANQADCgUIBQABNQAFFAUIEgAIAC4cAA==.',
Ao='Aoefarm:BAAANQADCggIGAAAAA==.',
Aq='Aqulath:BAABNQAECn8mAAIJAAoKEiD8AwATAwAJAAoKEiD8AwATAwAAAA==.',
Ar='Aragos:BAAANQADCgEIAQAAAA==.Arcanizzon:BAAANQADCggICAAAAA==.Ardênt:BAAANQADCgIIAgAAAA==.Aridhol:BAAANQAECgUICQAAAA==.',
As='Ashaala:BAAANQABCgIIBgAAAA==.Astravelle:BAAANQAECgQICgAAAA==.',
At='Athená:BAAANQAECgUICQAAAA==.Athenä:BAABNQAECn8kAAIKAAoKoxvyHACyAgAKAAoKoxvyHACyAgAAAA==.',
Au='Aubrii:BAAANQAECgMIBgAAAA==.Aukatsang:BAABNQAECn8dAAMLAAgK8x4dEwDBAgALAAgK8x4dEwDBAgAMAAEKvAy9EwA/AAAAAA==.',
Ay='Ayo:BAAANQADCgcIBwAAAA==.',
Az='Azeloth:BAAANQAECgYIEAAAAA==.',
Ba='Babzx:BAAANQADCgcICgAAAA==.Baladeva:BAABNQAECn8eAAINAAgKHSEUDwCrAgANAAgKHSEUDwCrAgAAAA==.Balekin:BAAANQAECgYICAAAAA==.Banaritaz:BAABNQAECn8XAAIBAAcKwxpCtAAbAgABAAcKwxpCtAAbAgAAAA==.Barbaricboss:BAAANQAECgQIBQAAAA==.Barrak:BAABNQAECn8YAAMOAAkKCA4yeQCgAQAOAAgK9w4yeQCgAQAPAAQKCgtY/ACZAAABNQAECgoKHQACAIcSAA==.Bau:BAAANQADCgYICgAAAA==.',
Be='Bearomir:BAABNQAECn8iAAIQAAoKLRynBQDDAgAQAAoKLRynBQDDAgAAAA==.Beersnob:BAABNQAECn8fAAILAAgKmAtFMwB8AQALAAgKmAtFMwB8AQAAAA==.',
Bh='Bhis:BAAANQADCgMIBgAAAA==.',
Bi='Bigblcktotem:BAACNQAFFH8aAAIPAAUKYhZJDQCaAQAPAAUKYhZJDQCaAQA1AAQKfyUAAg8ACgp9H/oQAGYDAA8ACgp9H/oQAGYDAAAA.Bigmikeyg:BAABNQAECn8gAAICAAgKRgp70wB1AQACAAgKRgp70wB1AQAAAA==.Bigsteve:BAABNQAECn8dAAMRAAgK/RbpgAAZAgARAAgKlxbpgAAZAgAQAAEK1htYLABTAAAAAA==.',
Bl='Bloodhunter:BAAANQADCgUIBwAAAA==.',
Bo='Bojak:BAAANQAECgEIAQAAAA==.Boomchickun:BAAANQABCgIIAgABNQAFFAUIDQASAHERAA==.',
Br='Brandie:BAAANQADCgUIBgAAAA==.Brickley:BAAANQADCgYIBgABNQAECgoKJgAJABIgAA==.Bronzesun:BAAANQADCggICAAAAA==.',
Bu='Bubbahowl:BAAANQADCgUIBQAAAA==.',
['Bè']='Bèyork:BAABNQAECn8eAAIOAAkKPBRAYADuAQAOAAkKPBRAYADuAQAAAA==.',
['Bø']='Bønd:BAAANQAECgMIAwAAAA==.',
Ca='Caicos:BAECNQAFFH8GAAITAAQK+wEeCwCcAAATAAQK+wEeCwCcAAA1AAQKfzcABBMACgoyD/8FACYBABMACgoyD/8FACYBABQAAwotCihBAJgAABUAAQpXAQ0pABkAAAAA.Calizon:BAAANQAECggIEQAAAA==.Camc:BAAANQADCgQIBwAAAA==.Canowhoopass:BAABNQAECn8fAAIPAAcKyQR1OADhAAAPAAcKyQR1OADhAAAAAA==.Caser:BAAANQADCgMJAwAAAA==.Caseynovak:BAAANQADCgUIBQAAAA==.Catharsis:BAAANQAECgMIAgAAAA==.',
Ce='Celenus:BAAANQAECggIDwAAAA==.Cell:BAACNQAFFH8RAAIRAAcKpQvDDgDIAQARAAcKpQvDDgDIAQA1AAQKfzsAAxEACgqRIucNAIsDABEACgqRIucNAIsDABYABAo1GhsMAO0AAAAA.Cellyne:BAAANQADCgUIBgAAAA==.Cerassin:BAACNQAFFH8NAAISAAUKcRHaAwDiAAASAAUKcRHaAwDiAAA1AAQKfzAAAhIACgq4HMQRAN4CABIACgq4HMQRAN4CAAAA.Cereall:BAAANQAECgIIAwAAAA==.Cereas:BAABNQAECn8kAAIKAAoK2BI0EgBZAQAKAAoK2BI0EgBZAQAAAA==.',
Ch='Cheesedawg:BAAANQADCgEIAQAAAA==.Cherrish:BAAANQADCgYICgAAAA==.Chevota:BAEANQADCggIBwABNQAFFAQIBgATAPsBAA==.Chicoh:BAAANQABCgYIBgAAAA==.Choofz:BAAANQADCggIEAAAAA==.',
Cl='Clariel:BAAANQAECgEIAQAAAA==.Cloud:BAABNQAECn8lAAIRAAoK4xScTwCbAgARAAoK4xScTwCbAgAAAA==.Clukdogg:BAABNQAECn8UAAIXAAgKRxobfAAWAgAXAAgKRxobfAAWAgAAAA==.',
Co='Combination:BAACNQAFFH8WAAMYAAYK1RKYBADPAAAZAAUKCRNNBwD2AAAYAAMKBwyYBADPAAA1AAQKfz8AAxkACgrwHm8FAGQCABgACQq+F/0FALACABkACQr6Hm8FAGQCAAAA.Corva:BAAANQAECgMIAwABNQAECgUIDwAFAAAAAA==.Corvenall:BAABNQAECn8oAAITAAkKRxIHBABgAQATAAkKRxIHBABgAQAAAA==.',
Cr='Crashpad:BAAANQAECgUIBwAAAA==.Crosben:BAAANQABCgQIBwAAAA==.Crossbow:BAABNQAECn8uAAIXAAoKkRf4QACoAgAXAAoKkRf4QACoAgAAAA==.',
Da='Daggers:BAAANQAECgUIBQAAAA==.Dakkan:BAAANQADCggIDAAAAA==.Dallarth:BAAANQADCgUIBQAAAA==.Danidani:BAABNQAECn8lAAIaAAoKTB8QIgDmAgAaAAoKTB8QIgDmAgAAAA==.Darkluster:BAAANQADCgQIBAAAAA==.Darrknes:BAAANQAECgEIAQAAAA==.Darshun:BAAANQADCgUICgAAAA==.Davinah:BAAANQAECgYIDAAAAA==.Dayje:BAAANQADCgUICAAAAA==.',
De='Deathation:BAAANQAECgEIAQABNQAECgUIDwAFAAAAAA==.Deathbcmesyu:BAAANQAECgUIDQAAAA==.Demonovest:BAABNQAECn8YAAIZAAgKlwSN0QAmAQAZAAgKlwSN0QAmAQAAAA==.Demontoarch:BAAANQADCggICAAAAA==.',
Di='Diehappy:BAAANQAECgEIAQAAAA==.Dishonor:BAAANQADCgYIDwAAAA==.',
Do='Dommage:BAABNQAECn8cAAIBAAkKzx6rAwC4AgABAAkKzx6rAwC4AgABNQAFFAUIEgAbAOYfAA==.Donkyote:BAAANQADCgEIAQAAAA==.Downbadd:BAAANQABCgQIBQAAAA==.',
Dr='Druida:BAABNQAECn8gAAQEAAoKQw2MHQDbAAAEAAkKcQ6MHQDbAAAGAAYK0wiDLQCrAAAbAAEKAACoXwA1AAAAAA==.Drywar:BAACNQAFFH8SAAIRAAUKHhoaEgCgAQARAAUKHhoaEgCgAQA1AAQKfyUAAhEACgryHnY4AOMCABEACgryHnY4AOMCAAAA.Dràgonkíng:BAAANQAECgMIAgAAAA==.',
Dt='Dtinnel:BAABNQAECn8bAAIRAAgKThGOmQDcAQARAAgKThGOmQDcAQABNQAFFAMICgAcAJIcAA==.',
['Dà']='Dànger:BAAANQAECgYIDAAAAA==.',
Ef='Efran:BAAANQABCgIIAgAAAA==.',
Eg='Ego:BAABNQAECn8vAAIRAAoK6R7ZAwC0AgARAAoK6R7ZAwC0AgAAAA==.',
Ei='Eisla:BAABNQAECn8eAAIHAAgK0ROQPADfAQAHAAgK0ROQPADfAQAAAA==.',
El='Elfor:BAAANQADCggIDAABNQAECgoKJAAKANgSAA==.',
Em='Emmone:BAAANQAECgQICAAAAA==.',
Ex='Exacerbator:BAAANQADCgYIGAAAAA==.',
Fa='Falcon:BAAANQABCgQIBQAAAA==.Fargecia:BAAANQAECgYICQAAAA==.Faunna:BAABNQAECn80AAIGAAoKCRvYIADGAgAGAAoKCRvYIADGAgAAAA==.',
Fe='Fearbomb:BAAANQADCgQIBAAAAA==.Feath:BAAANQADCgIIAgAAAA==.Feebeeboofae:BAABNQAECn8gAAMBAAoKPwRsJwFKAQABAAkKPwRsJwFKAQAdAAEKAABbVAAbAAAAAA==.Felaz:BAABNQAECn8zAAIBAAkKBhjUDQD8AQABAAkKBhjUDQD8AQAAAA==.Feoridor:BAAANQADCgIIAgAAAA==.Festy:BAAANQADCggIDgAAAA==.',
Fi='Fingerguns:BAABNQAECn83AAMaAAoKDSHJDABdAwAaAAoKDSHJDABdAwAeAAUK2wboFQDNAAAAAA==.Fionaa:BAAANQADCggIBwAAAA==.',
Fl='Floortank:BAABNQAECn8bAAIfAAYKhgYxPACyAAAfAAYKhgYxPACyAAAAAA==.',
Fr='Friday:BAABNQAECn8iAAMOAAoKqxSMSABAAgAOAAoKqxSMSABAAgAPAAQK+AtlTACrAAAAAA==.Frikilatar:BAAANQAECgEIAQAAAA==.Frrank:BAACNQAFFH8RAAIRAAUKQCaYBABGAQARAAUKQCaYBABGAQA1AAQKfy4AAhEACgqeJmMDAN4DABEACgqeJmMDAN4DAAAA.',
Ga='Galcain:BAABNQAECn8uAAMXAAoKsyObJgD9AgAXAAoKxSKbJgD9AgAgAAcKwhguMADMAQAAAA==.Garbagio:BAAANQABCggIDwAAAA==.',
Go='Googleyes:BAAANQADCgYIEAAAAA==.Goremaul:BAAANQAECgEIAQAAAA==.Goss:BAAANQADCgYICAAAAA==.',
Gr='Graphene:BAAANQADCgUIEgAAAA==.Greybull:BAAANQAECgQJCwAAAA==.Griffy:BAAANQADCgQIBAAAAA==.Grimseek:BAABNQAECn8iAAIgAAgK/hVzIwAyAgAgAAgK/hVzIwAyAgABNQAFFAYIFgAYANUSAA==.Growlyr:BAABNQAECn8iAAMcAAoKKyG3GgDsAgAcAAoKKyG3GgDsAgAfAAEKChiPpwA+AAAAAA==.Grumandel:BAABNQAECn8gAAIDAAgKyhXJDwARAgADAAgKyhXJDwARAgAAAA==.',
Ha='Hailstrike:BAAANQAECggIEAAAAA==.Hakur:BAABNQAECn8zAAICAAoKcA5UKACGAQACAAoKcA5UKACGAQAAAA==.Halfpink:BAAANQAECgQICQABNQAECgcIGAAGACYYAA==.Hammertóe:BAAANQADCggIGgAAAA==.Hanma:BAABNQAECn8hAAIcAAkKWx0pBAAEAgAcAAkKWx0pBAAEAgAAAA==.Harribel:BAABNQAECn8eAAMBAAgK9AXcEwFrAQABAAcKLgbcEwFrAQAdAAIKdQSuFABgAAAAAA==.',
He='Heiferina:BAAANQAECgcIEQAAAA==.Helixra:BAAANQAECgUICQAAAA==.Helixstorm:BAAANQAECgIIAgAAAA==.Hellcroh:BAACNQAFFH8NAAQYAAUK4BE9AgCqAAAZAAQKFgjzIADvAAAYAAIK7xI9AgCqAAAhAAEKAADACAAAAAA1AAQKfxQABBgACQoIHnMUAMsBABkACApLFTl3AP0BABgABQqyHXMUAMsBACEAAgoYHX8HALkAAAAA.Help:BAAANQADCgcIBwAAAA==.',
Hi='Hiyodam:BAAANQADCgUIAwAAAA==.Hiyodaw:BAAANQADCgIIAgAAAA==.Hizzon:BAAANQAECgMIAwAAAA==.',
Hy='Hyperíon:BAAANQAECgEIAQAAAA==.',
Ic='Icies:BAABNQAECn8mAAIdAAcK4BVkDAD1AQAdAAcK4BVkDAD1AQAAAA==.',
Il='Ilos:BAAANQAECgcIDQAAAA==.',
Im='Immafrogger:BAAANQAECgYICQABNQAECgoKJgAaAPsgAA==.',
Is='Iselle:BAAANQADCgYIBgAAAA==.Ishamaël:BAAANQADCgUIBQABNQAECgkJHwAPAHgXAA==.',
Ja='Jacora:BAAANQAECggICAAAAA==.Jailene:BAAANQAECgcIBwAAAA==.Jalian:BAAANQADCgIIAgAAAA==.Jawny:BAAANQADCgUIBQAAAA==.',
Jc='Jclif:BAABNQAECn8pAAIBAAgKhBLGvgAHAgABAAgKhBLGvgAHAgAAAA==.',
Je='Jehannum:BAABNQAECn8eAAIPAAgKoQ6HfQCrAQAPAAgKoQ6HfQCrAQAAAA==.Jessira:BAAANQAECgUJDwAAAA==.',
Jo='Jonahheal:BAABNQAECn8WAAIiAAkKRB1CHAADAwAiAAkKRB1CHAADAwABNQAFFAcIFwAOANYfAA==.Josen:BAABNQAECn8ZAAINAAcKUBfSHgDxAQANAAcKUBfSHgDxAQAAAA==.',
Ka='Kach:BAAANQAECgIIAgAAAA==.Kaefaith:BAAANQAECgEIAQAAAA==.Kaimi:BAAANQADCgQIEQAAAA==.Kainiy:BAAANQADCgcIHgAAAA==.Kaizenn:BAAANQADCgIIAgAAAA==.Kaladjin:BAABNQAECn8iAAQLAAoKWBLsJAD9AQALAAoKSxLsJAD9AQAMAAcKgAfJGwAqAQAjAAYKDgywLgD1AAAAAA==.Katarena:BAABNQAECn8iAAIiAAkKAwmihACNAQAiAAkKAwmihACNAQAAAA==.Kathyra:BAEBNQAECn81AAMZAAkKHBV3OQCnAgAZAAkKHBV3OQCnAgAYAAEKfwLghgAhAAABNQAFFAQIBgATAPsBAA==.Kavax:BAABNQAECn8XAAIiAAYK1BEfkABtAQAiAAYK1BEfkABtAQAAAA==.',
Ke='Keel:BAAANQADCgEIAQAAAA==.Keeller:BAAANQAECgMIBAAAAA==.Keggor:BAAANQAECgEIAgAAAA==.Keleris:BAAANQADCgcIDAAAAA==.Kelorth:BAAANQADCgcIBgAAAA==.Kentyr:BAAANQADCgQIBQAAAA==.Kez:BAAANQAECgQIBAAAAA==.',
Kh='Khasket:BAAANQAECgEIAQAAAA==.',
Ki='Kinký:BAABNQAECn8jAAIRAAgKHRLekwDqAQARAAgKHRLekwDqAQABNQADCgcIBwAFAAAAAA==.Kiraelis:BAABNQAECn8kAAIgAAgKNxdBJQAjAgAgAAgKNxdBJQAjAgAAAA==.',
Ko='Konvik:BAAANQADCgUICwAAAA==.Korvoh:BAABNQAECn8iAAIeAAgKhxTDCADUAQAeAAgKhxTDCADUAQAAAA==.',
Kr='Kragar:BAAANQADCgIIAgAAAA==.Kredriel:BAAANQAECgEJAQAAAA==.Krinmate:BAACNQAFFH8UAAIaAAYK5xsXCAAKAgAaAAYK5xsXCAAKAgA1AAQKfygAAxoACgqkEThlAPABABoACgpcEThlAPABAB4ABQpTByoWAMkAAAAA.Krystn:BAAANQAECgIIAgAAAA==.',
Ku='Kumaro:BAAANQABCgYIBgAAAA==.Kuurome:BAAANQADCgMIAwABNQAFFAMICgAcAJIcAA==.',
Kw='Kwinny:BAABNQAECn8iAAIiAAkK8hq6LwCnAgAiAAkK8hq6LwCnAgAAAA==.',
Ky='Kyloris:BAAANQAECggIAgAAAA==.Kynalin:BAAANQADCgEIAQAAAA==.Kynthria:BAAANQAECgYIDwABNQAECgoKFwABAOkeAA==.',
['Kä']='Kämik:BAABNQAECn8eAAMXAAgKFhdRfgARAgAXAAgKFhdRfgARAgAgAAEKAACZjAAyAAAAAA==.',
['Kì']='Kìn:BAAANQADCgQIBQAAAA==.',
La='Lampion:BAABNQAECn8jAAISAAoKPgcWMQC4AQASAAoKPgcWMQC4AQAAAA==.Landon:BAAANQADCgYIBgABNQAECgkJIwAcAOIdAA==.Latinamaddog:BAABNQAECn8nAAIZAAkK9xrnCQAJAgAZAAkK9xrnCQAJAgAAAA==.',
Le='Leijona:BAAANQADCggIHwAAAA==.Lelathon:BAAANQAECggICgAAAA==.Lenard:BAAANQAECgYICAAAAA==.Leröth:BAAANQAECgQIBQAAAA==.',
Li='Lightstorms:BAAANQADCgcIBwAAAA==.Likeatrain:BAABNQAECn8jAAMWAAYKhQy0EQCrAAAWAAYKhQy0EQCrAAARAAEKAAAU4gAAAAAAAA==.Lilwagyu:BAAANQAECgYIBgAAAA==.Linds:BAABNQAECn8UAAIiAAcKtROxbgDMAQAiAAcKtROxbgDMAQAAAA==.',
Lo='Lokininja:BAAANQAECgEIAgAAAA==.Lokki:BAAANQADCgYIBgAAAA==.Loofuh:BAAANQADCgYIBgAAAA==.Loopdog:BAAANQAECgQIBAAAAA==.',
Lt='Ltdanslegs:BAABNQAECn8kAAILAAoKuxqgFgCZAgALAAoKuxqgFgCZAgAAAA==.',
Lu='Luardreu:BAAANQADCgQIBAAAAA==.Luxu:BAABNQAECn8xAAIkAAoKWR9GDgA9AwAkAAoKWR9GDgA9AwAAAA==.Luxzy:BAAANQAECgUIBwAAAA==.',
Ma='Magdog:BAAANQADCgMIAwAAAA==.Magicbarbee:BAAANQADCgYJDAAAAA==.Makarich:BAAANQAECgQICAAAAA==.Malachron:BAAANQAECgYIDwAAAA==.Manbearcat:BAABNQAECn8YAAIGAAcKJhjHSwC1AQAGAAcKJhjHSwC1AQAAAA==.Manzanoso:BAAANQADCggIFAAAAA==.Marbleous:BAABNQAECn8rAAIRAAgKjiANPgDRAgARAAgKjiANPgDRAgAAAA==.',
Mc='Mcpink:BAAANQADCgUICQABNQAECgcIGAAGACYYAA==.',
Me='Meatcurtains:BAAANQADCgUIBQABNQAECgkJIwAcAOIdAA==.Melancholic:BAAANQADCggICQABNQAECgQICAAFAAAAAA==.Melhina:BAAANQAECgQIBAABNQAECggIHQAhAEkYAA==.Memisstotem:BAABNQAECn8fAAMOAAkK4QsYegCdAQAOAAgKTQwYegCdAQAPAAUKAhKvsgAtAQAAAA==.Merle:BAABNQAECn8pAAMRAAkK1x8fLwABAwARAAkK1x8fLwABAwAQAAUKPxksGAAcAQAAAA==.',
Mi='Minaxy:BAABNQAECn80AAICAAkKJB9yKgAdAwACAAkKJB9yKgAdAwAAAA==.Miranza:BAAANQAECgYIBQAAAA==.Mistborn:BAAANQAECgcIDgABNQAECgcIFwABAMMaAA==.Mistodon:BAAANQABCgcIDwAAAA==.Mistsofpoly:BAAANQAECgIIAQABNQAFFAYIEQAOABYOAA==.Mizzon:BAAANQADCgMIAwAAAA==.',
Mo='Momoku:BAABNQAECn8gAAIDAAgKexxNCwB6AgADAAgKexxNCwB6AgAAAA==.Moolimbo:BAAANQAECgUIBQABNQAECggILQAGABUVAA==.Mootalstrike:BAAANQAECgcIEwAAAA==.Moshworm:BAABNQAECn8hAAIGAAcKOgn7ZAA5AQAGAAcKOgn7ZAA5AQAAAA==.',
Mu='Muramasa:BAAANQAECgcIBwABNQAFFAMICgAcAJIcAA==.',
Mv='Mvp:BAAANQADCgcIEAAAAA==.',
Na='Namis:BAAANQAECgQIBQAAAA==.',
Ne='Nelaphim:BAABNQAECn8fAAMdAAkK7BeUCwAHAgAdAAkK7BeUCwAHAgABAAYK2AusHQFaAQAAAA==.Nexassin:BAAANQAECgEIAgAAAA==.',
Ni='Nico:BAABNQAECn8bAAIXAAkKTBrBQgCjAgAXAAkKTBrBQgCjAgAAAA==.Nightfang:BAAANQADCggIBQAAAA==.Nimz:BAAANQAECgYIDwABNQAECgkJIwAcAOIdAA==.',
No='Noxxidari:BAABNQAECn8kAAISAAoK6xVVGQCQAgASAAoK6xVVGQCQAgAAAA==.Noxxus:BAABNQAECn8bAAINAAoKvhTsEAAJAQANAAoKvhTsEAAJAQABNQAECgoKJAASAOsVAA==.',
Ny='Nymphis:BAAANQADCgQIBgAAAA==.Nymunandria:BAAANQADCgUIBQAAAA==.Nymz:BAAANQAECgIIAgABNQAECgkJIwAcAOIdAA==.',
Oa='Oakenshade:BAAANQADCgMIAgAAAA==.',
Ob='Oblivia:BAAANQADCggIBAAAAA==.Obsidiansoul:BAAANQAECgMIAwAAAA==.',
On='Onagne:BAAANQAECgEIAQABNQAECgkJKwARAD8eAA==.Onepunch:BAAANQADCgcIBwAAAA==.',
Or='Orchist:BAABNQAECn8XAAIQAAYKTh5eCwANAgAQAAYKTh5eCwANAgAAAA==.Orimbo:BAABNQAECn8tAAMGAAgKFRVbXABgAQAGAAYKEhFbXABgAQAEAAMK+QbDNABfAAAAAA==.',
['Oð']='Oðynn:BAAANQAECggICAABNQAECgIIAgAFAAAAAA==.',
Pa='Paidu:BAACNQAFFH8RAAQJAAUKVxL1AADTAAAKAAQKthN3DQA2AQAJAAQKwBD1AADTAAASAAEKSwP+FwA1AAA1AAQKfywABAkACgquHr0AAIkCAAkACAqdHr0AAIkCAAoACAopGk0oAFwCABIACAqzCj00AKEBAAAA.Palaritaz:BAAANQAECgIIBAABNQAECgcIFwABAMMaAA==.',
Pe='Pestilancé:BAABNQAECn8iAAIfAAgKnwNabwDhAAAfAAgKnwNabwDhAAAAAA==.',
Ph='Phenothal:BAAANQADCgUIBQAAAA==.',
Pi='Pinktp:BAAANQAECgIIAgAAAA==.Pion:BAAANQADCgQIBAAAAA==.Pitchblende:BAABNQAECn8rAAIiAAgKhRGxZwDgAQAiAAgKhRGxZwDgAQAAAA==.',
Po='Polylock:BAAANQAECggIBQAAAA==.Portiaa:BAAANQAECgcIDwAAAA==.Pothette:BAAANQADCgMIAwABNQAECgkJLwAlAJUaAA==.',
Pr='Prangkim:BAAANQADCgUICwAAAA==.Protagoras:BAAANQADCgQIBAAAAA==.',
Pu='Purejoy:BAAANQAECgQIBQAAAA==.',
Qu='Quickslice:BAAANQADCgcJBwAAAA==.Quillz:BAAANQAECgUIEQAAAA==.',
Ra='Rajak:BAAANQADCgMIAwAAAA==.Rathidk:BAACNQAFFH8MAAIkAAUKgR1bCgCyAQAkAAUKgR1bCgCyAQA1AAQKf0EAAiQACQq0JCgGAJIDACQACQq0JCgGAJIDAAAA.',
Re='Redine:BAAANQADCgcICgAAAA==.Reen:BAAANQADCgcICQAAAA==.Rellt:BAAANQAECgIIAQAAAA==.Rendis:BAAANQAECgQIBQAAAA==.',
Rh='Rhayge:BAABNQAECn8iAAMIAAgKqhLjGADYAQAIAAcK9hDjGADYAQAOAAYK6gd80QDEAAAAAA==.',
Ri='Riemann:BAAANQABCggICwAAAA==.',
Ro='Roxas:BAAANQADCgIIAgAAAA==.',
Ru='Ruukia:BAACNQAFFH8KAAIcAAMKkhzWAgDzAAAcAAMKkhzWAgDzAAA1AAQKf0oAAhwACgqwJYEHAIgDABwACgqwJYEHAIgDAAAA.',
Sa='Saboo:BAABNQAECn8oAAIhAAgKtBeIBgBDAgAhAAgKtBeIBgBDAgAAAA==.Sahki:BAAANQADCgUIDAAAAA==.Saltybreath:BAABNQAECn8gAAIUAAcKIBePHQD1AQAUAAcKIBePHQD1AQABNQAECgoKJAALALsaAA==.Sapientia:BAABNQAECn8bAAICAAcKowa87gA/AQACAAcKowa87gA/AQAAAA==.Savagex:BAAANQADCgMIAwAAAA==.',
Sc='Scottkill:BAAANQADCggIDAABNQAFFAcIFgABACwSAA==.',
Se='Seasnan:BAAANQAECgIIAQAAAA==.Segur:BAAANQABCgIIAgAAAA==.Seluna:BAAANQAECgcIEgAAAA==.Senapally:BAAANQADCgQIBAABNQAECgkJHwAXACUeAA==.Senlock:BAAANQABCgIIAgABNQAECgkJHwAXACUeAA==.',
Sh='Shadizzon:BAAANQADCgQIBAAAAA==.Shadowcloak:BAAANQABCgMIAwAAAA==.Shadowdeath:BAABNQAECn8iAAIfAAgK1wRJYAAkAQAfAAgK1wRJYAAkAQAAAA==.Shadowheàrt:BAAANQAECgYIEQAAAA==.Shadowshifty:BAAANQADCgcJBwAAAA==.Shadowtotem:BAAANQAECgcIDAAAAA==.Shagi:BAAANQAECgIIAgAAAA==.Shamdü:BAABNQAECn86AAIRAAoK7SCnFgBfAwARAAoK7SCnFgBfAwAAAA==.Shanson:BAAANQAECgYICwAAAA==.Sharroz:BAAANQAECgIIBAAAAA==.Shizuuku:BAAANQAECgEIAQABNQAFFAMICgAcAJIcAA==.Shockybalboa:BAABNQAECn8UAAIPAAcK1wgWmgBkAQAPAAcK1wgWmgBkAQAAAA==.Showerthots:BAAANQAECgIIAgAAAA==.',
Si='Silvver:BAAANQADCgcIBwAAAA==.Sineth:BAAANQADCggIEAAAAA==.',
Sk='Skooda:BAABNQAECn8tAAIPAAoK3RD7UAA1AgAPAAoK3RD7UAA1AgAAAA==.Skybles:BAAANQAECgIIAwAAAA==.Skyded:BAAANQADCgUIBQAAAA==.Skyfell:BAABNQAECn8nAAISAAgKyxf2JgANAgASAAgKyxf2JgANAgAAAA==.Skyknight:BAABNQAECn8aAAIQAAkK1RjdCABSAgAQAAkK1RjdCABSAgAAAA==.',
Sl='Sloan:BAAANQADCgMIAwAAAA==.',
Sn='Snapahead:BAAANQAECgEIAQAAAA==.Sneakpeak:BAAANQABCgQIBgAAAA==.',
So='Solcon:BAABNQAECn8ZAAIKAAgKgBgDNQAGAgAKAAgKgBgDNQAGAgAAAA==.Solence:BAAANQADCggIHAAAAA==.Somebodie:BAAANQAECgMIAwAAAA==.',
Sp='Spaazz:BAABNQAECn8hAAICAAgKnhfVmwDrAQACAAgKnhfVmwDrAQAAAA==.Sparkwire:BAAANQADCggICAAAAA==.',
Sq='Squeakbolt:BAAANQADCgcIDwAAAA==.',
St='Starofdreams:BAAANQADCgEIAQABNQAECgoKJAAaAHIMAA==.Staroflight:BAAANQADCgMIAwABNQAECgoKJAAaAHIMAA==.Starweaver:BAABNQAECn8kAAMaAAoKcgzEZwDoAQAaAAoKcgzEZwDoAQAeAAEKtgFQMwAZAAAAAA==.Stormrender:BAABNQAECn8tAAMLAAkKMBPUJQD1AQALAAkKMBPUJQD1AQAjAAIKLwUoSABJAAAAAA==.Stormsong:BAACNQAFFH8FAAIPAAMKuxFVGgDvAAAPAAMKuxFVGgDvAAA1AAQKfxkAAw8ACQqlHOE1AKACAA8ACQqlHOE1AKACAA4AAwryCg3wAIoAAAAA.Strangecandy:BAAANQAECgcICwAAAA==.Strangrdangr:BAAANQADCgQIBAAAAA==.Strángeland:BAAANQAECgIIAgAAAA==.Störmrender:BAAANQAECgEIAQABNQAECgkJLQALADATAA==.',
Su='Sublïminals:BAABNQAECn8kAAQiAAkKciLYAACSAwAiAAkKciLYAACSAwACAAcKmRqnmQDwAQANAAMKkCGHRQDaAAAAAA==.Suhalo:BAAANQADCgMIAwAAAA==.Sunarianna:BAAANQAECgcIDQAAAA==.Superpull:BAAANQAECgUICQABNQABCgIIAgAFAAAAAA==.',
Sy='Sycla:BAABNQAECn8jAAMYAAoKVxm3GACmAQAZAAgK5xb5iwDJAQAYAAYKMBi3GACmAQAAAA==.Syedrine:BAAANQADCggIBgAAAA==.Sylas:BAAANQAECgQICAAAAA==.',
Ta='Tab:BAAANQAECgEIAQAAAA==.Taloriesh:BAAANQAECgQICwAAAA==.Tanazir:BAEANQAECgIIAwAAAA==.Tarok:BAAANQADCgUICgAAAA==.Tashien:BAAANQAECgUIBwAAAA==.',
Te='Tealzin:BAAANQABCgQIBQAAAA==.Techytechy:BAAANQAECgYIBgAAAA==.Teito:BAAANQAECgYIEwABNQAECgkJGwACACEfAA==.Terenii:BAAANQAECgIIAgAAAA==.',
Ti='Tilamano:BAABNQAECn8lAAQZAAoKfyPRDQBgAwAZAAoKKyPRDQBgAwAYAAYK7CIWCgBWAgAhAAUKIyIGCwDAAQAAAA==.Tilatree:BAAANQAECgEIAgABNQAECgoKJQAZAH8jAA==.Tillidari:BAAANQAECgQIAwABNQAECgoKJQAZAH8jAA==.',
To='Tohrnarc:BAABNQAECn8fAAIBAAkKvx7eOABMAQABAAkKvx7eOABMAQAAAA==.Tookkiiee:BAAANQAECggICwAAAA==.Totem:BAAANQAECgQIBgAAAA==.Totemwebz:BAABNQAECn8XAAIOAAYKyCBsUgAdAgAOAAYKyCBsUgAdAgAAAA==.',
Tr='Trenve:BAABNQAECn8oAAIEAAkKAR9+AgCoAgAEAAkKAR9+AgCoAgAAAA==.',
Ts='Tseirpa:BAAANQADCgQIBQAAAA==.',
Tu='Turbomage:BAAANQADCgcIBwAAAA==.Tuzzyfits:BAABNQAECn8qAAIOAAgK4xzfNgCDAgAOAAgK4xzfNgCDAgAAAA==.',
Tw='Twojayzz:BAAANQAECggIEAAAAA==.',
Ty='Tyrethia:BAAANQAECgUIDwAAAA==.',
['Té']='Téchymoon:BAACNQAFFH8HAAIYAAMKYgODDACfAAAYAAMKYgODDACfAAA1AAQKf0YAAhgACgqXGkUAAHkCABgACgqXGkUAAHkCAAAA.',
Ug='Uggaibo:BAAANQADCgQIBAAAAA==.Ugo:BAAANQAECgQIBAAAAA==.',
Um='Umbron:BAABNQAECn8jAAQHAAkKcRk+HACcAgAHAAkKDhg+HACcAgAmAAcK9xhJHQDoAQAnAAEKMA+DHAAvAAAAAA==.',
Un='Undertaker:BAAANQABCggIDAAAAA==.',
Va='Valcristo:BAABNQAECn8fAAINAAkKqCIBDwCsAgANAAkKqCIBDwCsAgAAAA==.Valdun:BAAANQADCgcIEQAAAA==.Vanaras:BAAANQADCgYIBwAAAA==.Vargrim:BAABNQAECn8pAAIZAAcKkwQrYwC8AAAZAAcKkwQrYwC8AAAAAA==.',
Ve='Venous:BAABNQAECn8cAAMHAAgK6hJFSQCfAQAHAAcKMBJFSQCfAQAmAAYKwA6iKgBuAQAAAA==.Vestt:BAAANQADCggIFQAAAA==.',
Vi='Vicariana:BAACNQAFFH8SAAMoAAUKpx+dAgAgAQAoAAQKpx+dAgAgAQAaAAMK1QIPJAC6AAA1AAQKfz4ABCgACgpLIhEBALcCACgACQqfIREBALcCAB4ABgpnJJAEAH4CABoACQqgFvBQADECAAAA.Victhyr:BAAANQAECgUICQAAAA==.Vidette:BAAANQADCggIEwAAAA==.Viduus:BAABNQAECn8jAAMcAAkK4h1VIgC9AgAcAAgKSCFVIgC9AgAfAAcKnRYZQgC9AQAAAA==.Viv:BAABNQAECn8dAAMCAAoKORFimgDuAQACAAoKORFimgDuAQAiAAMKEyCTuwAFAQAAAA==.',
Vo='Vodmor:BAABNQAECn8WAAICAAcK/QI9HgHsAAACAAcK/QI9HgHsAAAAAA==.Voldermort:BAAANQADCgcIEwAAAA==.',
Wa='Warrendemon:BAAANQAFFAIIAgAAAA==.',
We='Wedowarcrime:BAAANQADCgIIAgAAAA==.',
Wh='Whims:BAABNQAECn8YAAIYAAYKlg4XHQCFAQAYAAYKlg4XHQCFAQAAAA==.',
Wi='Wildheart:BAAANQAECgEIAgAAAA==.Wingchún:BAAANQAECgEIAQAAAA==.',
Wo='Woregontail:BAAANQAECgIIBAAAAA==.Wowbelly:BAAANQAECggIEQAAAA==.',
Xa='Xalrissa:BAAANQADCgUICgAAAA==.Xandeath:BAAANQAECgYICgAAAA==.Xandem:BAAANQAECgUIBAAAAA==.Xandros:BAABNQAECn8VAAIhAAcKKxBQCwC3AQAhAAcKKxBQCwC3AQAAAA==.Xanlight:BAAANQADCgIIAgAAAA==.',
Xo='Xonk:BAACNQAFFH8KAAIhAAQKCA56AADlAAAhAAQKCA56AADlAAA1AAQKfy8AAyEACgrqGTwEAJ8CACEACgrqGTwEAJ8CABgAAQqMG2JoAFEAAAAA.',
Yg='Ygcamel:BAAANQADCggIEgAAAA==.',
Yi='Yiazmat:BAAANQABCgcICwAAAA==.',
Za='Zaklu:BAAANQAECgIIBAAAAA==.Zalagrimbor:BAABNQAECn8fAAMPAAkKeBcKRwBaAgAPAAkKeBcKRwBaAgAOAAMKgAWC/wBrAAAAAA==.Zalathar:BAAANQABCgQIBAAAAA==.Zaps:BAABNQAECn8nAAIPAAgKxCHQIgD9AgAPAAgKxCHQIgD9AgAAAA==.Zarev:BAACNQAFFH8QAAIgAAYKchlBBgDzAQAgAAYKchlBBgDzAQA1AAQKfyoAAiAACQoAI4cNAAYDACAACQoAI4cNAAYDAAAA.',
Ze='Zeenab:BAAANQADCgIIAgAAAA==.Zegrath:BAAANQADCgcJDAABNQAECgIIAgAFAAAAAA==.Zelie:BAABNQAECn8fAAMOAAkK6Qu9gACKAQAOAAkK6Qu9gACKAQAPAAUK4wDHDwFsAAAAAA==.Zenreto:BAABNQAECn8iAAIHAAgKPRajMgATAgAHAAgKPRajMgATAgAAAA==.',
Zh='Zhuri:BAAANQADCggICgAAAA==.',
Zo='Zoeri:BAAANQAECgEIAQAAAA==.Zoltraak:BAAANQADCgYIDwAAAA==.',
['Än']='Änmoa:BAACNQAFFH8SAAIIAAUKLhxGAgC5AQAIAAUKLhxGAgC5AQA1AAQKfzQAAggACgoKI7sBAJ0DAAgACgoKI7sBAJ0DAAAA.',
['Ïn']='Ïnsane:BAAANQAECgIIAgAAAA==.',
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
