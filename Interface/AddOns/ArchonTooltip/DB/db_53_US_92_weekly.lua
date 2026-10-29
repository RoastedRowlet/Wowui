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

local lookup = {'Mage-Arcane','Paladin-Retribution','Druid-Feral','Druid-Restoration','Unknown-Unknown','Druid-Balance','Rogue-Assassination','Shaman-Enhancement','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Warrior-Protection','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Priest-Holy','Druid-Guardian','DeathKnight-Unholy','Mage-Frost','Priest-Discipline','DeathKnight-Frost','Hunter-Marksmanship','DeathKnight-Blood','Warlock-Affliction','Paladin-Holy','Monk-Mistweaver','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw','Priest-Shadow',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abrakådabruh:BAABNQAECn8iAAIBAAgKfRDBygDwAQABAAgKfRDBygDwAQAAAA==.Absolverator:BAAANQADCgQIBAAAAA==.Abzero:BAAANQAECgIIAgAAAA==.',
Ac='Acnologia:BAAANQAECgQIBwAAAA==.',
Ae='Aeropos:BAAANQABCgEIAQAAAA==.',
Ah='Ahron:BAABNQAECn8hAAICAAoK/hOofAAxAgACAAoK/hOofAAxAgAAAA==.',
Ai='Ainjel:BAAANQAECgIIAwAAAA==.Ainz:BAAANQAECgEIAQAAAA==.',
Ak='Akaitsuki:BAABNQAECn8mAAMDAAkKkRQ3DwAeAgADAAkKkRQ3DwAeAgAEAAQKzAEcZAB1AAAAAA==.',
Al='Alex:BAAANQAECgEIAQAAAA==.Alexdh:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.Alexmg:BAAANQAECgEIAgAAAA==.Alexr:BAAANQAECgEIAQAAAA==.Alexxh:BAAANQADCgMIAwABNQAECgEIAQAFAAAAAA==.',
Am='Amarantus:BAAANQAECgcIDAABNQAECgoKPgAGABccAA==.Amarndeus:BAAANQAECgEIAQAAAA==.Ammerie:BAAANQADCgUJBQAAAA==.Ampkhwa:BAAANQADCggIBwAAAA==.',
An='Anmoa:BAABNQAECn8eAAIHAAgKphlfIAB/AgAHAAgKphlfIAB/AgABNQAFFAYIEwAIAJoWAA==.Anmodru:BAAANQADCgUIBQABNQAFFAYIEwAIAJoWAA==.',
Ao='Aoefarm:BAAANQADCggIGAAAAA==.',
Aq='Aqulath:BAACNQAFFH8FAAIJAAEKah+gAwBZAAAJAAEKah+gAwBZAAA1AAQKfyoAAgkACgpgIfwDABMDAAkACgpgIfwDABMDAAAA.',
Ar='Aragos:BAAANQADCgEIAQAAAA==.Arcanizzon:BAAANQADCggICAAAAA==.Ardênt:BAAANQADCgIIAgAAAA==.Aridhol:BAAANQAECgYICgAAAA==.',
As='Ashaala:BAAANQABCgIIBgAAAA==.Ashanor:BAAANQAECgEIAQAAAA==.Astravelle:BAAANQAECgQICgAAAA==.',
At='Athená:BAAANQAECgUIDAAAAA==.Athenä:BAABNQAECn8qAAIKAAoKmRzyHACyAgAKAAoKmRzyHACyAgAAAA==.',
Au='Aubrii:BAAANQAECgMIBgAAAA==.Aukatsang:BAABNQAECn8hAAMLAAkKKyEdEwDBAgALAAkKKyEdEwDBAgAMAAEKvAxLHAA5AAAAAA==.',
Ay='Ayo:BAAANQADCgcIBwAAAA==.',
Az='Azeloth:BAAANQAECgYIEQAAAA==.',
Ba='Babzx:BAAANQADCgcICgAAAA==.Baladeva:BAABNQAECn8gAAINAAgKHSEUDwCrAgANAAgKHSEUDwCrAgAAAA==.Balekin:BAAANQAECgYICAAAAA==.Banaritaz:BAABNQAECn8XAAIBAAcKwxpCtAAbAgABAAcKwxpCtAAbAgAAAA==.Barbaricboss:BAAANQAECgQIBwAAAA==.Barrak:BAABNQAECn8cAAMOAAoKQg4yeQCgAQAOAAgKuxAyeQCgAQAPAAUK5AtklgByAAABNQAECgoKIQACAP4TAA==.Bau:BAAANQADCgYICgAAAA==.',
Be='Bearomir:BAABNQAECn8mAAIQAAoK3B2nBQDDAgAQAAoK3B2nBQDDAgAAAA==.Beersnob:BAABNQAECn8iAAILAAkKeAtFMwB8AQALAAkKeAtFMwB8AQAAAA==.',
Bh='Bhis:BAAANQADCgMIBgAAAA==.',
Bi='Bigblcktotem:BAACNQAFFH8aAAIPAAUKYhZJDQCaAQAPAAUKYhZJDQCaAQA1AAQKfy0AAg8ACgo0I/oQAGYDAA8ACgo0I/oQAGYDAAAA.Bigmikeyg:BAABNQAECn8iAAICAAgKmQp70wB1AQACAAgKmQp70wB1AQAAAA==.Bigsteve:BAABNQAECn8eAAMRAAgKPhnpgAAZAgARAAgK1xjpgAAZAgAQAAEK1htYLABTAAAAAA==.',
Bl='Bloodhunter:BAAANQADCgUIBwAAAA==.',
Bo='Bojak:BAAANQAECgIIAwAAAA==.Boomchickun:BAAANQAECgEIAQABNQAFFAYIEgASAGwWAA==.',
Br='Brandie:BAAANQADCgUIBgAAAA==.Brickley:BAAANQADCgYIBgABNQAFFAEIBQAJAGofAA==.Bronzesun:BAAANQADCggICAAAAA==.',
Bu='Bubbahowl:BAAANQADCgUIBQAAAA==.',
['Bè']='Bèyork:BAABNQAECn8mAAIOAAkKJxU3MwDSAQAOAAkKJxU3MwDSAQAAAA==.',
['Bø']='Bønd:BAAANQAECgQICgAAAA==.',
Ca='Caicos:BAECNQAFFH8GAAITAAQK+wEeCwCcAAATAAQK+wEeCwCcAAA1AAQKfzcABBMACgoyDxUSADECABMACgoyDxUSADECABQAAwotCihBAJgAABUAAQpXAQ0pABkAAAAA.Calizon:BAABNQAECn8aAAINAAoKxAp5GgAqAQANAAoKxAp5GgAqAQAAAA==.Camc:BAAANQADCgQIBwAAAA==.Canowhoopass:BAABNQAECn8lAAIPAAcKoQVwagDQAAAPAAcKoQVwagDQAAAAAA==.Caser:BAAANQADCgMJAwAAAA==.Caseynovak:BAAANQADCgUIBQAAAA==.Catharsis:BAAANQAECgMIAwAAAA==.',
Ce='Celenus:BAAANQAECggIEAAAAA==.Cell:BAACNQAFFH8RAAIRAAcKpQvDDgDIAQARAAcKpQvDDgDIAQA1AAQKf0gAAxEACgq3IucNAIsDABEACgq3IucNAIsDABYABAo1GtUXANYAAAAA.Cellyne:BAAANQADCgUIBgAAAA==.Cerassin:BAACNQAFFH8SAAISAAYKbBaqAgBBAQASAAYKbBaqAgBBAQA1AAQKfzoAAhIACgp+HYUIAHkCABIACgp+HYUIAHkCAAAA.Cereall:BAAANQAECgQICAAAAA==.Cereas:BAABNQAECn8mAAIKAAoK2BLCLAA9AgAKAAoK2BLCLAA9AgAAAA==.',
Ch='Cheesedawg:BAAANQADCgEIAQAAAA==.Cherrish:BAAANQADCgcICwAAAA==.Chevota:BAEANQADCggIBwABNQAFFAQIBgATAPsBAA==.Chicoh:BAAANQABCgYIBgAAAA==.Choofz:BAAANQADCggIEAAAAA==.',
Cl='Clariel:BAAANQAECgEIAgAAAA==.Cloud:BAABNQAECn8sAAIRAAoKbxpyMAAWAgARAAoKbxpyMAAWAgAAAA==.Clukdogg:BAABNQAECn8UAAIXAAgKRxobfAAWAgAXAAgKRxobfAAWAgAAAA==.',
Co='Combination:BAACNQAFFH8XAAMYAAcKog+YBADPAAAZAAYK/A6cBwAyAQAYAAMKBwyYBADPAAA1AAQKf0YAAxgACgqYH/0FALACABkACQrFHxMnAOgCABgACQq+F/0FALACAAAA.Corva:BAAANQAECgQIBAABNQAECgcIFAARADUaAA==.Corvenall:BAABNQAECn8wAAITAAoKjBPsBwCSAQATAAoKjBPsBwCSAQAAAA==.Corwyn:BAABNQAECn8vAAIZAAcKqgRskgDLAAAZAAcKqgRskgDLAAAAAA==.',
Cr='Crashpad:BAAANQAECgUICgAAAA==.Crosben:BAAANQAECgIIAwAAAA==.Crossbow:BAABNQAECn8vAAIXAAoKkRf4QACoAgAXAAoKkRf4QACoAgAAAA==.',
Da='Daggers:BAAANQAECgUIBgAAAA==.Dakkan:BAAANQADCggIDAAAAA==.Dallarth:BAAANQADCgUIBQAAAA==.Danglyudders:BAAANQADCgEIAQAAAA==.Danidani:BAABNQAECn8sAAIaAAoK6R8QIgDmAgAaAAoK6R8QIgDmAgAAAA==.Darkluster:BAAANQADCgQIBAAAAA==.Darrknes:BAAANQAECgEIBQAAAA==.Darshun:BAAANQADCgUICgAAAA==.Davand:BAAANQABCgIIAgAAAA==.Davinah:BAAANQAECggIDwAAAA==.Dayje:BAAANQADCgUICAAAAA==.Dazarn:BAAANQADCgEIAQAAAA==.',
De='Deathation:BAAANQAECgEIAQABNQAECgcIFAARADUaAA==.Deathbcmesyu:BAAANQAECgUIDQAAAA==.Demonovest:BAABNQAECn8aAAIZAAgKzQSN0QAmAQAZAAgKzQSN0QAmAQAAAA==.Demontoarch:BAAANQADCggICAAAAA==.',
Di='Diehappy:BAAANQAECgIIAwAAAA==.Dishonor:BAAANQADCgYIDwAAAA==.',
Do='Dommage:BAABNQAECn8mAAIBAAoK2SH1DADwAgABAAoK2SH1DADwAgABNQAFFAYIEwAbAL0fAA==.Donkyote:BAAANQADCgEIAQAAAA==.Downbadd:BAAANQABCgQIBQAAAA==.',
Dr='Drizzon:BAAANQAECgEIAQAAAA==.Druida:BAABNQAECn8mAAQEAAoKRw7QIgBGAQAEAAkKkw/QIgBGAQAGAAcKGgqoOwDXAAAbAAEKAACoXwA1AAAAAA==.Drywar:BAACNQAFFH8SAAIRAAUKHhoaEgCgAQARAAUKHhoaEgCgAQA1AAQKfy0AAhEACgpFI/4nAEQCABEACgpFI/4nAEQCAAAA.Dràgonkíng:BAAANQAECgQIBAAAAA==.',
Dt='Dtinnel:BAABNQAECn8cAAIRAAgKThGOmQDcAQARAAgKThGOmQDcAQABNQAFFAQICwAcAJIcAA==.',
Du='Duck:BAAANQAECgEIAwAAAA==.',
['Dà']='Dànger:BAAANQAECgYIDwAAAA==.',
Ec='Echidna:BAAANQAECgQIBAAAAA==.',
Ef='Efran:BAAANQABCgIIAgAAAA==.',
Eg='Ego:BAABNQAECn84AAIRAAoKiCECEwDNAgARAAoKiCECEwDNAgAAAA==.',
Ei='Eisla:BAABNQAECn8eAAIHAAgK0ROQPADfAQAHAAgK0ROQPADfAQAAAA==.',
El='Elfor:BAAANQADCggIDAABNQAECgoKJgAKANgSAA==.Elpicosito:BAAANQAECgIIAgAAAA==.',
Em='Emmone:BAAANQAECgQICgAAAA==.',
Ep='Epiconx:BAAANQADCgEIAQAAAA==.',
Ex='Exacerbator:BAAANQAECgEIAQAAAA==.',
Fa='Falcon:BAAANQABCgQIBQAAAA==.Fargecia:BAAANQAECgYICQAAAA==.Farglight:BAAANQAECgEIAQAAAA==.Faunna:BAABNQAECn8+AAIGAAoKFxwxDwBVAgAGAAoKFxwxDwBVAgAAAA==.',
Fe='Fearbomb:BAAANQAECgEIAgAAAA==.Feath:BAAANQADCgIIAgAAAA==.Feebeeboofae:BAABNQAECn8gAAMBAAoKPwRsJwFKAQABAAkKPwRsJwFKAQAdAAEKAABbVAAbAAAAAA==.Feet:BAAANQAECgEIAgAAAA==.Felaz:BAABNQAECn88AAIBAAoKyRc6MwAkAgABAAoKyRc6MwAkAgAAAA==.Feoridor:BAAANQADCgIIAgAAAA==.Festy:BAAANQADCggIDgAAAA==.',
Fi='Fingerguns:BAACNQAFFH8GAAIaAAMKwxdxEwD5AAAaAAMKwxdxEwD5AAA1AAQKf0EAAxoACgoWJJUBAAMEABoACgoWJJUBAAMEAB4ABQrbBugVAM0AAAAA.Fionaa:BAAANQADCggIBwAAAA==.',
Fl='Floortank:BAABNQAECn8hAAIfAAcKnQa0TQDfAAAfAAcKnQa0TQDfAAAAAA==.',
Fr='Friday:BAABNQAECn8tAAMOAAoKkxYVIQA9AgAOAAoKkxYVIQA9AgAPAAQK+AvXhQCSAAAAAA==.Frikilatar:BAAANQAECgEIAgAAAA==.Frrank:BAACNQAFFH8SAAIRAAYKIyaQBACoAQARAAYKIyaQBACoAQA1AAQKfzsAAhEACgqoJjkBAIMDABEACgqoJjkBAIMDAAAA.',
Ga='Galcain:BAABNQAECn8uAAMXAAoKsyObJgD9AgAXAAoKxSKbJgD9AgAgAAcKwhguMADMAQAAAA==.Garbagio:BAAANQAECgEIAQAAAA==.',
Go='Googleyes:BAAANQADCgYIEAAAAA==.Goremaul:BAAANQAECgEIAQAAAA==.Goss:BAAANQADCgYICAAAAA==.',
Gr='Graphene:BAAANQAECgQIBAAAAA==.Greybull:BAAANQAECgQJCwAAAA==.Griffy:BAAANQADCgQIBAAAAA==.Grimseek:BAABNQAECn8lAAIgAAkKBxVzIwAyAgAgAAkKBxVzIwAyAgABNQAFFAcIFwAYAKIPAA==.Grimstar:BAAANQAECgEIAQAAAA==.Growlyr:BAABNQAECn8jAAMcAAoKCCK3GgDsAgAcAAoKCCK3GgDsAgAfAAEKChiPpwA+AAAAAA==.Grumandel:BAABNQAECn8iAAIDAAgKbRbJDwARAgADAAgKbRbJDwARAgAAAA==.',
Ha='Hailstrike:BAABNQAECn8cAAIhAAoKzRdZEwATAgAhAAoKzRdZEwATAgAAAA==.Hakur:BAABNQAECn88AAICAAoKXhGUWACtAQACAAoKXhGUWACtAQAAAA==.Halfpink:BAAANQAECgUIDgABNQAECgcIGAAGACYYAA==.Hamahara:BAAANQAECgEIAQAAAA==.Hammertóe:BAAANQADCggIGgAAAA==.Hanma:BAABNQAECn8mAAIcAAoKrBzGDABRAgAcAAoKrBzGDABRAgAAAA==.Harribel:BAABNQAECn8gAAMdAAgKZwk5HQCGAAABAAcKLgbcEwFrAQAdAAIK6g85HQCGAAAAAA==.',
He='Heiferina:BAABNQAECn8dAAIXAAoKJQl4VACfAQAXAAoKJQl4VACfAQAAAA==.Helixra:BAAANQAECgUICQAAAA==.Helixstorm:BAAANQAECgIIAgAAAA==.Hellcroh:BAACNQAFFH8OAAQYAAYKSRJzAAAAAQAYAAMKIRNzAAAAAQAZAAQKFgjzIADvAAAiAAEKAACcDgAAAAA1AAQKfxgABBgACQpeHnMUAMsBABkACArEFTl3AP0BABgABQqyHXMUAMsBACIAAgoYHTsOAKoAAAAA.Help:BAAANQADCgcIDAAAAA==.',
Hi='Hiyodam:BAAANQADCgUIAwAAAA==.Hiyodaw:BAAANQADCgIIAgAAAA==.Hizzon:BAAANQAECggIDQAAAA==.',
Hy='Hyperíon:BAAANQAECgEIAwAAAA==.',
Ic='Icies:BAABNQAECn8pAAIdAAcK4BVkDAD1AQAdAAcK4BVkDAD1AQAAAA==.',
Il='Ilos:BAAANQAECgcIEAAAAA==.',
Im='Immafrogger:BAAANQAECgYICgABNQAECgoKJgAaAPsgAA==.',
Is='Iselle:BAAANQADCgYIBgAAAA==.Ishamaël:BAAANQADCgUIBQABNQAECgkJHwAPAHgXAA==.',
Ja='Jacora:BAAANQAECggICAAAAA==.Jailene:BAAANQAECgcICAAAAA==.Jalian:BAAANQADCgIIAgAAAA==.Jawny:BAAANQADCgUIBQAAAA==.',
Jc='Jclif:BAABNQAECn8vAAIBAAoKGRHwVACuAQABAAoKGRHwVACuAQAAAA==.',
Je='Jehannum:BAABNQAECn8fAAIPAAgKhRCHfQCrAQAPAAgKhRCHfQCrAQAAAA==.Jessira:BAAANQAECgUJEgAAAA==.',
Jo='Jonahheal:BAABNQAECn8WAAIjAAkKRB1CHAADAwAjAAkKRB1CHAADAwABNQAFFAcIGAAOANYfAA==.Josen:BAABNQAECn8aAAINAAcKUBfSHgDxAQANAAcKUBfSHgDxAQAAAA==.',
Ka='Kach:BAAANQAECgIIAwAAAA==.Kaefaith:BAAANQAECgEIAQAAAA==.Kaimi:BAAANQADCgQIEQAAAA==.Kainiy:BAAANQADCgcIHgAAAA==.Kaizenn:BAAANQADCgIIAgAAAA==.Kaladjin:BAABNQAECn8iAAQLAAoKWBLsJAD9AQALAAoKSxLsJAD9AQAMAAcKgAfJGwAqAQAkAAYKDgywLgD1AAAAAA==.Katarena:BAABNQAECn8jAAIjAAkKAwmihACNAQAjAAkKAwmihACNAQAAAA==.Kathyra:BAEBNQAECn81AAMZAAkKHBV3OQCnAgAZAAkKHBV3OQCnAgAYAAEKfwLghgAhAAABNQAFFAQIBgATAPsBAA==.Kavax:BAABNQAECn8XAAIjAAYK1BEfkABtAQAjAAYK1BEfkABtAQAAAA==.',
Ke='Keel:BAAANQADCgEIAQAAAA==.Keeller:BAAANQAECgMIBAAAAA==.Keggor:BAAANQAECgEIBQAAAA==.Keleris:BAAANQADCgcIDAAAAA==.Kelorth:BAAANQADCgcIBgAAAA==.Kentyr:BAAANQADCgQIBQAAAA==.Kez:BAAANQAECgQIBAAAAA==.',
Kh='Khasket:BAAANQAECgEIAgAAAA==.',
Ki='Kinký:BAABNQAECn8lAAIRAAoKqhDekwDqAQARAAoKqhDekwDqAQABNQAECgEIAQAFAAAAAA==.Kiraelis:BAABNQAECn8qAAIgAAoKGBdUDwDUAQAgAAoKGBdUDwDUAQAAAA==.',
Ko='Konvik:BAAANQADCgUICwAAAA==.Korvoh:BAABNQAECn8kAAIeAAgKThXDCADUAQAeAAgKThXDCADUAQAAAA==.',
Kr='Kragar:BAAANQADCgIIAgAAAA==.Kredriel:BAAANQAECgEJAQAAAA==.Krinmate:BAACNQAFFH8UAAIaAAYK5xsXCAAKAgAaAAYK5xsXCAAKAgA1AAQKfygAAxoACgqkEThlAPABABoACgpcEThlAPABAB4ABQpTByoWAMkAAAAA.Krystn:BAAANQAECgIIBgAAAA==.',
Ku='Kumaro:BAAANQABCgYIBgAAAA==.Kuurome:BAAANQADCgMIAwABNQAFFAQICwAcAJIcAA==.',
Kw='Kwinny:BAABNQAECn8jAAIjAAkK9Rq6LwCnAgAjAAkK9Rq6LwCnAgAAAA==.',
Ky='Kyloris:BAAANQAECggIAwAAAA==.Kynalin:BAAANQADCgEIAQAAAA==.Kynthria:BAAANQAECgYIEgABNQAECgoKGAABAOkeAA==.',
['Kä']='Kämik:BAABNQAECn8fAAMXAAgKFhdRfgARAgAXAAgKFhdRfgARAgAgAAEKAACZjAAyAAAAAA==.',
['Kì']='Kìn:BAAANQADCgQIBQAAAA==.',
La='Lampion:BAABNQAECn8jAAISAAoKPgcWMQC4AQASAAoKPgcWMQC4AQAAAA==.Landon:BAAANQADCgYIBgABNQAECgkJJQAcALoeAA==.Lasstchance:BAAANQAECgEIAwAAAA==.Latinamaddog:BAABNQAECn8qAAIZAAkKKRt3MADsAQAZAAkKKRt3MADsAQAAAA==.',
Le='Leijona:BAAANQAECgEIAQAAAA==.Lelathon:BAAANQAECggICwAAAA==.Lenard:BAAANQAECgYICAAAAA==.Leröth:BAAANQAECgQIBQAAAA==.Lesie:BAAANQAECgIIBAAAAA==.',
Li='Lightstorms:BAAANQADCgcIBwAAAA==.Lijepa:BAAANQABCgEIAQAAAA==.Likeatrain:BAABNQAECn8pAAMWAAcKMA3IFQDrAAAWAAcKMA3IFQDrAAARAAEKAADYFgEAAAAAAA==.Lilwagyu:BAAANQAECgYIBgAAAA==.Linds:BAABNQAECn8YAAIjAAkKBRSxbgDMAQAjAAkKBRSxbgDMAQAAAA==.',
Lo='Lokininja:BAAANQAECgEIBgAAAA==.Lokki:BAAANQADCgYIBgAAAA==.Loofuh:BAAANQADCgYIBgAAAA==.Loopdog:BAAANQAECgQIBwAAAA==.',
Lt='Ltdanslegs:BAABNQAECn8qAAILAAoKuRygFgCZAgALAAoKuRygFgCZAgAAAA==.',
Lu='Luardreu:BAAANQADCgQIBAAAAA==.Luxu:BAABNQAECn89AAIhAAoKUyBGDgA9AwAhAAoKUyBGDgA9AwAAAA==.Luxzy:BAAANQAECgYIEAAAAA==.',
Ma='Magdog:BAAANQADCgMIAwAAAA==.Magicbarbee:BAAANQADCgYJDAAAAA==.Makarich:BAAANQAECgYIDQAAAA==.Malachron:BAAANQAECgcIEQAAAA==.Manbearcat:BAABNQAECn8YAAIGAAcKJhjHSwC1AQAGAAcKJhjHSwC1AQAAAA==.Manzanoso:BAAANQADCggIGAAAAA==.Marbleous:BAABNQAECn8rAAIRAAgKjiANPgDRAgARAAgKjiANPgDRAgAAAA==.',
Mc='Mcpink:BAAANQADCgUICQABNQAECgcIGAAGACYYAA==.',
Me='Meatcurtains:BAAANQADCgUIBQABNQAECgkJJQAcALoeAA==.Melancholic:BAAANQAECgEIAQABNQAECgYIDQAFAAAAAA==.Melhina:BAAANQAECgQIBAABNQAECggIHwAiAEkYAA==.Memisstotem:BAABNQAECn8fAAMOAAkK4QsYegCdAQAOAAgKTQwYegCdAQAPAAUKAhKvsgAtAQAAAA==.Merle:BAABNQAECn8wAAMRAAkKWCAfLwABAwARAAkKWCAfLwABAwAQAAUKPxksGAAcAQAAAA==.',
Mi='Mikarri:BAAANQAECgEIAgAAAA==.Minaxy:BAABNQAECn88AAICAAkKqB9yKgAdAwACAAkKqB9yKgAdAwAAAA==.Miranza:BAAANQAECgYIBwAAAA==.Mistborn:BAAANQAECgcIEAABNQAECgcIFwABAMMaAA==.Mistodon:BAAANQAECgEIAQAAAA==.Mistsofpoly:BAAANQAECgIIBQABNQAFFAYIEQAOABYOAA==.Mizzon:BAAANQADCggICwAAAA==.',
Mo='Momoku:BAABNQAECn8iAAIDAAgKhR1NCwB6AgADAAgKhR1NCwB6AgAAAA==.Moolimbo:BAAANQAECgcIDAABNQAECgoKNAAGAMIUAA==.Mootalstrike:BAAANQAECgcIEwAAAA==.Moshworm:BAABNQAECn8kAAIGAAcKkAn7ZAA5AQAGAAcKkAn7ZAA5AQAAAA==.',
Mu='Muramasa:BAAANQAECgcICgABNQAFFAQICwAcAJIcAA==.',
Mv='Mvp:BAAANQADCgcIEAAAAA==.',
Na='Nalaxx:BAAANQAECgEIAQAAAA==.Namis:BAAANQAECgUIBwAAAA==.',
Ne='Nelaphim:BAABNQAECn8jAAMdAAkKvRqUCwAHAgAdAAkKvRqUCwAHAgABAAYK2AusHQFaAQAAAA==.Neversneaky:BAAANQAECgcICAABNQAECgoKHAAhAM0XAA==.Nexassin:BAAANQAECgQIBgAAAA==.',
Ni='Nico:BAABNQAECn8iAAIXAAkKExytJwBDAgAXAAkKExytJwBDAgAAAA==.Nightfang:BAAANQADCggIBQAAAA==.Nimz:BAABNQAECn8UAAQYAAcK2x8lHgB9AQAZAAcK+RTwowCNAQAYAAUK/h8lHgB9AQAiAAEKAACjLgA5AAABNQAECgkJJQAcALoeAA==.',
No='Noctrine:BAAANQAECgEIAgAAAA==.Noxxidari:BAABNQAECn8vAAISAAoK+Bq1DQARAgASAAoK+Bq1DQARAgAAAA==.Noxxus:BAABNQAECn8hAAINAAoKwBR9EwBxAQANAAoKwBR9EwBxAQABNQAECgoKLwASAPgaAA==.',
Ny='Nymphis:BAAANQADCgQIBgAAAA==.Nymunandria:BAAANQADCgUIBQAAAA==.Nymz:BAAANQAECgcICQABNQAECgkJJQAcALoeAA==.',
Oa='Oakenshade:BAAANQADCgYICAAAAA==.',
Ob='Oblivia:BAAANQAECgEIAgAAAA==.Obsidiansoul:BAAANQAECgMIBAAAAA==.',
Og='Oghma:BAAANQAECgYICAAAAA==.',
Ol='Oldmans:BAAANQADCgIIAgAAAA==.',
Om='Omnivus:BAAANQAECgEIBAAAAA==.',
On='Onagne:BAAANQAECgEIAQABNQAECgoKMAARAFseAA==.Onepunch:BAAANQADCgcIBwAAAA==.',
Or='Orchist:BAABNQAECn8XAAIQAAYKTh5eCwANAgAQAAYKTh5eCwANAgAAAA==.Orimbo:BAABNQAECn80AAMGAAoKwhS/OQDhAAAGAAcKDxC/OQDhAAAEAAQKLQZkRAB9AAAAAA==.',
['Oð']='Oðynn:BAAANQAECggICQABNQAECgIIBgAFAAAAAA==.',
Pa='Paidu:BAACNQAFFH8SAAQJAAYK9RCQAQDEAAAKAAUKaBF3DQA2AQAJAAQKwBCQAQDEAAASAAEKSwP+FwA1AAA1AAQKfzIABAkACgquHkcDAF0CAAkACAqdHkcDAF0CAAoACQqlHk0oAFwCABIACAqzCj00AKEBAAAA.Palaritaz:BAAANQAECgIIBAABNQAECgcIFwABAMMaAA==.',
Pe='Pestilancé:BAABNQAECn8kAAIfAAgKuwNabwDhAAAfAAgKuwNabwDhAAAAAA==.',
Ph='Phenothal:BAAANQADCgYIBgAAAA==.',
Pi='Pingpaung:BAAANQAECgQIBAAAAA==.Pinktp:BAAANQAECgIIAgAAAA==.Pion:BAAANQADCgQIBAAAAA==.Pitchblende:BAABNQAECn8xAAIjAAoKDRN1QwCIAQAjAAoKDRN1QwCIAQAAAA==.',
Po='Polylock:BAAANQAECggIDgAAAA==.Portiaa:BAABNQAECn8VAAMBAAgKZwiDEQFvAQABAAcKYgeDEQFvAQAdAAIKgA1WNgBjAAAAAA==.Pothette:BAAANQADCgMIAwABNQAECgoKMwAlANEZAA==.',
Pr='Prangkim:BAAANQADCgUICwAAAA==.Protagoras:BAAANQADCgQIBAAAAA==.',
Pu='Purejoy:BAAANQAECgQIBgAAAA==.',
Qu='Quickslice:BAAANQADCgcJBwAAAA==.Quillz:BAABNQAECn8UAAIWAAUKihUuGADTAAAWAAUKihUuGADTAAAAAA==.',
Ra='Rajak:BAAANQADCgMIAwAAAA==.Raszageth:BAAANQAECgEIAQAAAA==.Rathidk:BAACNQAFFH8NAAIhAAYKuhtbCgCyAQAhAAYKuhtbCgCyAQA1AAQKf04AAiEACgr0IygGAJIDACEACgr0IygGAJIDAAAA.',
Re='Redine:BAAANQADCgcICgAAAA==.Reen:BAAANQADCgcICQAAAA==.Rellt:BAAANQAECgIIBAAAAA==.Rendis:BAAANQAECgQIBwAAAA==.',
Rh='Rhayge:BAABNQAECn8kAAMIAAgKvQ/jGADYAQAIAAgKvQ/jGADYAQAOAAYK6gd80QDEAAAAAA==.',
Ri='Riemann:BAAANQABCggICwAAAA==.',
Ro='Roxas:BAAANQADCgIIAgAAAA==.',
Ru='Ruukia:BAACNQAFFH8LAAIcAAQKkhzlBADxAAAcAAQKkhzlBADxAAA1AAQKf1gAAhwACgrbJYADABsDABwACgrbJYADABsDAAAA.',
Sa='Saboo:BAABNQAECn8uAAIiAAoKMxVeAwDwAQAiAAoKMxVeAwDwAQAAAA==.Sahki:BAAANQADCgUIDAAAAA==.Salion:BAAANQAECgEIAQAAAA==.Saltybreath:BAABNQAECn8iAAIUAAgKyhWPHQD1AQAUAAgKyhWPHQD1AQABNQAECgoKKgALALkcAA==.Sapientia:BAABNQAECn8bAAICAAcKowa87gA/AQACAAcKowa87gA/AQAAAA==.Savagex:BAAANQADCgMIAwAAAA==.',
Sc='Scottkill:BAAANQADCggIDAABNQAFFAcIFgABACwSAA==.',
Se='Seasnan:BAAANQAECgIIAgAAAA==.Segur:BAAANQABCgIIAgAAAA==.Seluna:BAABNQAECn8VAAIOAAgKCxIbbQDEAQAOAAgKCxIbbQDEAQAAAA==.Senapally:BAAANQADCgQIBAABNQAECgkJHwAXACUeAA==.Senlock:BAAANQABCgIIAgABNQAECgkJHwAXACUeAA==.',
Sh='Shadizzon:BAAANQADCgQIBAAAAA==.Shadowcloak:BAAANQABCgMIAwAAAA==.Shadowdeath:BAABNQAECn8qAAMfAAkKKQVJYAAkAQAfAAkKKQVJYAAkAQAcAAEK2gM0cwAqAAAAAA==.Shadowheàrt:BAABNQAECn8WAAIjAAcKpQt4nQBMAQAjAAcKpQt4nQBMAQAAAA==.Shadowshifty:BAAANQADCgcJBwAAAA==.Shadowtotem:BAAANQAECgcIEQAAAA==.Shagi:BAAANQAECgIIBAAAAA==.Shamdü:BAABNQAECn9DAAIRAAoKJiKnFgBfAwARAAoKJiKnFgBfAwAAAA==.Shanson:BAAANQAECgYICwAAAA==.Sharroz:BAAANQAECgIIBAAAAA==.Shizuuku:BAAANQAECgEIAQABNQAFFAQICwAcAJIcAA==.Shockybalboa:BAABNQAECn8VAAIPAAcK1wgWmgBkAQAPAAcK1wgWmgBkAQAAAA==.Showerthots:BAAANQAECgUIBgAAAA==.',
Si='Silvver:BAAANQADCgcIBwAAAA==.Sineth:BAAANQADCggIEAAAAA==.',
Sj='Sjóræningi:BAAANQAECgEIAQAAAA==.',
Sk='Skooda:BAABNQAECn83AAIPAAoKLhaVGwAfAgAPAAoKLhaVGwAfAgAAAA==.Skybles:BAAANQAECgMIBgAAAA==.Skyded:BAAANQADCgUIBQAAAA==.Skyfell:BAABNQAECn8qAAISAAoK8hT2JgANAgASAAoK8hT2JgANAgAAAA==.Skyknight:BAABNQAECn8iAAIQAAkK1RjdCABSAgAQAAkK1RjdCABSAgAAAA==.',
Sl='Sloan:BAAANQADCgMIAwAAAA==.',
Sn='Snapahead:BAAANQAECgEIAQAAAA==.Sneakpeak:BAAANQABCgQIBgAAAA==.',
So='Solcon:BAABNQAECn8bAAIKAAgKzhkDNQAGAgAKAAgKzhkDNQAGAgAAAA==.Solence:BAAANQAECgIIAwAAAA==.Somebodie:BAAANQAECgMICQAAAA==.',
Sp='Spaazz:BAABNQAECn8hAAICAAgKnhfVmwDrAQACAAgKnhfVmwDrAQAAAA==.Sparkwire:BAAANQADCggICAAAAA==.Speedrunner:BAAANQAECgEIAgAAAA==.',
Sq='Squeakbolt:BAAANQADCgcIDwAAAA==.',
St='Starofdreams:BAAANQADCgEIAQABNQAECgoKKwAaAAcQAA==.Staroflight:BAAANQAECgEIAgABNQAECgoKKwAaAAcQAA==.Starweaver:BAABNQAECn8rAAMaAAoKBxC5NADoAQAaAAoKBxC5NADoAQAeAAEKtgFQMwAZAAAAAA==.Stormrender:BAABNQAECn8zAAMLAAoKUBPzFQCOAQALAAoKUBPzFQCOAQAkAAMK1gUoSABJAAAAAA==.Stormsong:BAACNQAFFH8FAAIPAAMKuxFVGgDvAAAPAAMKuxFVGgDvAAA1AAQKfxkAAw8ACQqlHOE1AKACAA8ACQqlHOE1AKACAA4AAwryCg3wAIoAAAAA.Strangecandy:BAABNQAECn8fAAISAAkK+goUGgBhAQASAAkK+goUGgBhAQAAAA==.Strangrdangr:BAAANQADCgQIBAAAAA==.Strángeland:BAAANQAECgIIAgAAAA==.Störmrender:BAAANQAECgEIAQABNQAECgoKMwALAFATAA==.',
Su='Sublïminals:BAABNQAECn8uAAQjAAkKxyPnAwCjAwAjAAkKxyPnAwCjAwACAAcKmRqnmQDwAQANAAMKkCGHRQDaAAAAAA==.Suhalo:BAAANQADCgMIAwAAAA==.Sunarianna:BAABNQAECn8ZAAIBAAoKcRB0PgD7AQABAAoKcRB0PgD7AQAAAA==.Superpull:BAAANQAECgUICQABNQABCgIIAgAFAAAAAA==.',
Sy='Sycla:BAABNQAECn8lAAMYAAoKMhq3GACmAQAZAAgK4Rf5iwDJAQAYAAYKMBi3GACmAQAAAA==.Syedrine:BAAANQAECgUIBQAAAA==.Sylas:BAAANQAECgQICQAAAA==.',
Ta='Tab:BAAANQAECgUIBgAAAA==.Taloriesh:BAAANQAECgYIDwAAAA==.Tanazir:BAEANQAECgQICgAAAA==.Tarok:BAAANQADCgUICgAAAA==.Tashien:BAAANQAECgUICgAAAA==.',
Te='Tealzin:BAAANQABCgQIBQAAAA==.Techytechy:BAAANQAECgYIBgAAAA==.Teito:BAABNQAECn8XAAMOAAgK7BsVVAAXAgAOAAgK7BsVVAAXAgAPAAIKYyO0oABiAAAAAA==.Terenii:BAAANQAECgIIAgAAAA==.',
Ti='Tilamano:BAABNQAECn8nAAQZAAoKWSTRDQBgAwAZAAoKKyPRDQBgAwAYAAgKFSMWCgBWAgAiAAUKIyIGCwDAAQAAAA==.Tilatree:BAAANQAECgEIBAABNQAECgoKJwAZAFkkAA==.Tillidari:BAAANQAECgUICQABNQAECgoKJwAZAFkkAA==.',
To='Tohrnarc:BAABNQAECn8jAAIBAAkKlSCqiwBoAgABAAkKlSCqiwBoAgAAAA==.Tookkiiee:BAAANQAECggICwAAAA==.Totem:BAAANQAECgQICAAAAA==.Totemwebz:BAABNQAECn8YAAIOAAYKyCBsUgAdAgAOAAYKyCBsUgAdAgAAAA==.',
Tr='Trenve:BAABNQAECn8rAAIEAAkK0B8hCgCeAgAEAAkK0B8hCgCeAgAAAA==.',
Ts='Tseirpa:BAAANQAECgEIAQAAAA==.',
Tu='Turbomage:BAAANQADCgcIBwAAAA==.Tuzzyfits:BAABNQAECn8wAAIOAAoKqRvfNgCDAgAOAAoKqRvfNgCDAgAAAA==.',
Tw='Twojayzz:BAAANQAECggIEAAAAA==.',
Ty='Tyrethia:BAABNQAECn8UAAIRAAcKNRoXqwCxAQARAAcKNRoXqwCxAQAAAA==.',
['Té']='Téchymoon:BAACNQAFFH8HAAIYAAMKYgODDACfAAAYAAMKYgODDACfAAA1AAQKf1AAAhgACgomGwsBAG8CABgACgomGwsBAG8CAAAA.',
Ug='Uggaibo:BAAANQADCgYICAAAAA==.Ugo:BAAANQAECgQIBQAAAA==.',
Um='Umbron:BAABNQAECn8jAAQHAAkKcRk+HACcAgAHAAkKDhg+HACcAgAmAAcK9xhJHQDoAQAnAAEKMA+DHAAvAAAAAA==.Umbrute:BAAANQAECgEIAQABNQAECgkJIwAHAHEZAA==.',
Un='Undertaker:BAAANQAECgEIAgAAAA==.',
Va='Valcristo:BAABNQAECn8jAAINAAkKzCMBDwCsAgANAAkKzCMBDwCsAgAAAA==.Valdun:BAAANQADCgcIEQAAAA==.Vanaras:BAAANQADCgYIBwAAAA==.',
Ve='Venous:BAABNQAECn8gAAMHAAkK2xRFSQCfAQAHAAcKMBJFSQCfAQAmAAgKexCiKgBuAQAAAA==.Vestt:BAAANQADCggIFQAAAA==.',
Vi='Vicariana:BAACNQAFFH8TAAMoAAYKfiGrBAAUAQAoAAQKpx+rBAAUAQAaAAQKkgIPJAC6AAA1AAQKf0IABCgACgqDIeEFAMECACgACgqDIeEFAMECAB4ABgpnJJAEAH4CABoACQqgFvBQADECAAAA.Victhyr:BAAANQAECgUICQAAAA==.Vidette:BAAANQAECgEIAQAAAA==.Viduus:BAABNQAECn8lAAMcAAkKuh5VIgC9AgAcAAkKuh5VIgC9AgAfAAcKnRYZQgC9AQAAAA==.Viv:BAABNQAECn8nAAMCAAoKSRfgNQAhAgACAAoKSRfgNQAhAgAjAAMKEyCTuwAFAQAAAA==.',
Vo='Vodmor:BAABNQAECn8bAAICAAcKbwM9HgHsAAACAAcKbwM9HgHsAAAAAA==.Voldermort:BAAANQADCgcIEwAAAA==.',
Wa='Warrendemon:BAAANQAFFAIIAgAAAA==.',
We='Wedowarcrime:BAAANQAECgEIAQAAAA==.',
Wh='Whims:BAABNQAECn8fAAIYAAgKOg+nBwD6AAAYAAgKOg+nBwD6AAAAAA==.',
Wi='Wildheart:BAAANQAECgEIBAAAAA==.Windgoddess:BAAANQADCggICAAAAA==.Wingchún:BAAANQAECgYIBgAAAA==.',
Wo='Woregontail:BAAANQAECgQICQAAAA==.Wowbelly:BAABNQAECn8XAAIkAAoK+CC6CQDuAgAkAAoK+CC6CQDuAgAAAA==.',
Xa='Xalrissa:BAAANQADCgUICgAAAA==.Xandeath:BAAANQAECgcIDwAAAA==.Xandem:BAAANQAECgUIBQAAAA==.Xandros:BAABNQAECn8VAAIiAAcKKxBQCwC3AQAiAAcKKxBQCwC3AQAAAA==.Xanlight:BAAANQADCgIIAgAAAA==.',
Xo='Xonk:BAACNQAFFH8KAAIiAAQKCA7wAADcAAAiAAQKCA7wAADcAAA1AAQKfzMAAyIACgoVGjwEAJ8CACIACgoVGjwEAJ8CABgAAQqMG2JoAFEAAAAA.',
Yg='Ygcamel:BAAANQADCggIEgAAAA==.',
Yi='Yiazmat:BAAANQABCgcICwAAAA==.',
Za='Zaklu:BAAANQAECgIIBgAAAA==.Zalagrimbor:BAABNQAECn8fAAMPAAkKeBcKRwBaAgAPAAkKeBcKRwBaAgAOAAMKgAWC/wBrAAAAAA==.Zalathar:BAAANQABCgQIBAAAAA==.Zaps:BAABNQAECn8rAAIPAAoKeCDQIgD9AgAPAAoKeCDQIgD9AgAAAA==.Zarev:BAACNQAFFH8QAAIgAAYKchlBBgDzAQAgAAYKchlBBgDzAQA1AAQKfyoAAiAACQoAI4cNAAYDACAACQoAI4cNAAYDAAAA.',
Ze='Zeenab:BAAANQADCgIIAgAAAA==.Zegrath:BAAANQADCgcJDAABNQAECgIIBAAFAAAAAA==.Zelie:BAABNQAECn8jAAMOAAkK/gy9gACKAQAOAAkK/gy9gACKAQAPAAUK4wDHDwFsAAAAAA==.Zenira:BAAANQAECgEIAQAAAA==.Zenreto:BAABNQAECn8kAAIHAAgKSBejMgATAgAHAAgKSBejMgATAgAAAA==.',
Zh='Zhuri:BAAANQADCggIDAAAAA==.',
Zo='Zoeri:BAAANQAECgIIBAAAAA==.Zoltraak:BAAANQADCgYIDwAAAA==.',
['Än']='Änmoa:BAACNQAFFH8TAAIIAAYKmhYlAQAtAQAIAAYKmhYlAQAtAQA1AAQKfz8AAggACgqHJLsBAJ0DAAgACgqHJLsBAJ0DAAAA.',
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
