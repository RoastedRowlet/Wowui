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

local lookup = {'Mage-Arcane','Paladin-Retribution','Paladin-Holy','Druid-Feral','Druid-Restoration','Unknown-Unknown','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Shaman-Enhancement','DemonHunter-Vengeance','Druid-Guardian','DemonHunter-Havoc','Monk-Windwalker','Monk-Brewmaster','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Warrior-Protection','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Priest-Holy','DeathKnight-Unholy','Mage-Frost','Priest-Discipline','DeathKnight-Frost','Hunter-Marksmanship','DeathKnight-Blood','Warlock-Affliction','Monk-Mistweaver','Hunter-Survival','Priest-Shadow','Rogue-Outlaw',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abrakådabruh:BAABNQAECn8pAAIBAAoKtw7BygDwAQABAAoKtw7BygDwAQAAAA==.Absolverator:BAAANQADCgQIBAAAAA==.Abzero:BAAANQAECgIIAgAAAA==.',
Ac='Acnologia:BAAANQAECgQIBQAAAA==.',
Ae='Ae:BAAANQABCgYIDQAAAA==.Aeropos:BAAANQABCgEIAQAAAA==.',
Ah='Ahron:BAABNQAECn8wAAMCAAoKshaofAAxAgACAAoKshaofAAxAgADAAIKdwcb4wBSAAAAAA==.',
Ai='Ainjel:BAAANQAECgQIBwAAAA==.Ainz:BAAANQADCgYICgAAAA==.',
Ak='Akaitsuki:BAABNQAECn8pAAMEAAoKlBU3DwAeAgAEAAoKlBU3DwAeAgAFAAQKzAEcZAB1AAAAAA==.',
Al='Aleuseche:BAAANQAECgMIAwABNQAECgQIBAAGAAAAAA==.Alex:BAAANQAECgMIAwAAAA==.Alexdh:BAAANQADCgcIBwAAAA==.Alexr:BAAANQADCgUIBQABNQADCgcIBwAGAAAAAA==.Alexxh:BAAANQADCgMIAwABNQADCgcIBwAGAAAAAA==.Alisson:BAAANQADCgEIAQABNQADCgcIBwAGAAAAAA==.',
Am='Amarantus:BAAANQAECggIDAABNQAECgoKRAAHAOQdAA==.Amarndeus:BAAANQABCgcICQAAAA==.Ammerie:BAAANQADCgUJBQAAAA==.Ampkhwa:BAAANQADCggIBwAAAA==.',
An='Anmoa:BAABNQAECn8tAAMIAAgKJR13KgBWAgAJAAgKphlfIAB/AgAIAAgKeBt3KgBWAgABNQAFFAcIFAAKAK8XAA==.Anmodru:BAAANQADCgUIBQABNQAFFAcIFAAKAK8XAA==.',
Ao='Aoefarm:BAAANQADCggIGAAAAA==.',
Aq='Aqulath:BAACNQAFFH8IAAILAAMKDB2yAQD7AAALAAMKDB2yAQD7AAA1AAQKfy8AAgsACgpeIvwDABMDAAsACgpeIvwDABMDAAAA.',
Ar='Aragos:BAAANQADCgEIAQAAAA==.Arcanizzon:BAAANQADCggICAAAAA==.Ardênt:BAAANQADCgIIAgAAAA==.Aridhol:BAAANQAECgYICQAAAA==.',
As='Ashaala:BAAANQABCgIIBgAAAA==.Astravelle:BAABNQAECn8VAAIMAAYKGRj8JwBHAQAMAAYKGRj8JwBHAQAAAA==.',
At='Athená:BAAANQAECggIDQABNQAECgoKQQANAH4gAA==.Athenä:BAABNQAECn9BAAINAAoKfiCsCQD9AgANAAoKfiCsCQD9AgAAAA==.',
Au='Aubrii:BAAANQAECgUICQAAAA==.Aukatsang:BAABNQAECn8iAAMOAAkKKyEdEwDBAgAOAAkKKyEdEwDBAgAPAAEKvAxVJgA5AAAAAA==.',
Ay='Ayo:BAAANQADCgcIBwAAAA==.',
Az='Azeloth:BAAANQAECgYIEAAAAA==.',
Ba='Babzx:BAAANQADCgcICgAAAA==.Baladeva:BAABNQAECn8pAAIQAAoKGCEUDwCrAgAQAAoKGCEUDwCrAgAAAA==.Balekin:BAAANQAECgYICAAAAA==.Banaritaz:BAABNQAECn8XAAIBAAcKwxpCtAAbAgABAAcKwxpCtAAbAgAAAA==.Barbaricboss:BAAANQAECgQIBQAAAA==.Barrak:BAABNQAECn8oAAMRAAoK5hQmWwCpAQARAAkKshMmWwCpAQASAAUKxhB6kADpAAABNQAECgoKMAACALIWAA==.Bau:BAAANQADCgYICgAAAA==.',
Be='Bearomir:BAABNQAECn8mAAITAAoK3B2nBQDDAgATAAoK3B2nBQDDAgAAAA==.Beersnob:BAABNQAECn8iAAIOAAkKeAtFMwB8AQAOAAkKeAtFMwB8AQAAAA==.',
Bh='Bhis:BAAANQADCgMIBgAAAA==.',
Bi='Bigblcktotem:BAACNQAFFH8kAAISAAYKYhUQCgA8AQASAAYKYhUQCgA8AQA1AAQKfy4AAhIACgo0I/oQAGYDABIACgo0I/oQAGYDAAAA.Bigmikeyg:BAABNQAECn8pAAICAAkKrQt70wB1AQACAAkKrQt70wB1AQAAAA==.Bigsteve:BAABNQAECn8nAAMUAAoKAhnpgAAZAgAUAAoKtRjpgAAZAgATAAEK1htYLABTAAAAAA==.',
Bl='Bloodhunter:BAAANQADCgUIBwAAAA==.',
Bo='Bodysnatcher:BAAANQAECgUIBQAAAA==.Bojak:BAAANQAECgYIBgAAAA==.Boomchickun:BAAANQABCgIIAgABNQAFFAYIFgAVAGwWAA==.',
Br='Brandie:BAAANQADCgUIBgAAAA==.Brickley:BAAANQADCgYIBgABNQAFFAMICAALAAwdAA==.Bronzesun:BAAANQADCggIEAAAAA==.',
Bu='Bubbahowl:BAAANQADCgUIBQAAAA==.',
['Bè']='Bèyork:BAABNQAECn8sAAIRAAoKrxV3QAASAgARAAoKrxV3QAASAgAAAA==.',
['Bø']='Bønd:BAAANQAECgQIBgAAAA==.',
Ca='Caicos:BAECNQAFFH8GAAIWAAQK+wEeCwCcAAAWAAQK+wEeCwCcAAA1AAQKf1QABBYACgoGFXsIAPoBABYACgoGFXsIAPoBABcAAwotCihBAJgAABgAAQpXAQ0pABkAAAAA.Calizon:BAABNQAECn8hAAIQAAoKHwtwKAAvAQAQAAoKHwtwKAAvAQAAAA==.Camc:BAAANQADCgQIBwAAAA==.Canowhoopass:BAABNQAECn8uAAISAAkKugY4dAAuAQASAAkKugY4dAAuAQAAAA==.Caser:BAAANQADCgMIAwAAAA==.Caseynovak:BAAANQADCgUIBQAAAA==.Catharsis:BAAANQAECgIIAgAAAA==.',
Ce='Celenus:BAAANQAECggIDwAAAA==.Cell:BAACNQAFFH8RAAIUAAcKpQvDDgDIAQAUAAcKpQvDDgDIAQA1AAQKf0wAAxQACgpCI+cNAIsDABQACgpCI+cNAIsDABkABAo1GlQnAMEAAAAA.Cellyne:BAAANQADCgUIBgAAAA==.Cerassin:BAACNQAFFH8WAAIVAAYKbBZ1BQAgAQAVAAYKbBZ1BQAgAQA1AAQKf0wAAhUACgqNIpAFAAcDABUACgqNIpAFAAcDAAAA.Cereall:BAAANQAECgUICAAAAA==.Cereas:BAABNQAECn8xAAINAAoKahTCLAA9AgANAAoKahTCLAA9AgAAAA==.',
Ch='Cheesedawg:BAAANQADCgEIAQAAAA==.Cherrish:BAAANQADCgcICwAAAA==.Chevota:BAEANQADCggIBwABNQAFFAQIBgAWAPsBAA==.Chicoh:BAAANQABCgYIBgAAAA==.Choofz:BAAANQADCggIEAAAAA==.',
Cl='Clariel:BAAANQAECgEIAQAAAA==.Cloud:BAABNQAECn8sAAIUAAoKbxqcTwCbAgAUAAoKbxqcTwCbAgAAAA==.Clukdogg:BAABNQAECn8UAAIaAAgKRxobfAAWAgAaAAgKRxobfAAWAgAAAA==.',
Co='Combination:BAACNQAFFH8YAAMbAAgKOxGYBADPAAAcAAcKCBE0CgCEAQAbAAMKBwyYBADPAAA1AAQKf0sAAxsACgpmIf0FALACABwACQrVIRMnAOgCABsACQq+F/0FALACAAAA.Corva:BAAANQAECgMIBAABNQAECggIFwAUAGoYAA==.Corvenall:BAABNQAECn8/AAIWAAoKRxRbDACPAQAWAAoKRxRbDACPAQAAAA==.Corwyn:BAABNQAECn82AAIcAAoKlQTBmgAiAQAcAAoKlQTBmgAiAQAAAA==.',
Cr='Crashpad:BAAANQAECgUIBwAAAA==.Crosben:BAAANQAECgQIBgAAAA==.Crossbow:BAABNQAECn81AAIaAAoKLBj4QACoAgAaAAoKLBj4QACoAgAAAA==.Crynox:BAAANQADCgEIAQAAAA==.',
['Cõ']='Cõnker:BAAANQAECgIIAgAAAA==.',
Da='Daggers:BAAANQAECgUIBQAAAA==.Dakkan:BAAANQADCggIDAAAAA==.Dallarth:BAAANQAECgIIAgAAAA==.Danglyudders:BAAANQAECggIDAAAAA==.Danidani:BAABNQAECn80AAIdAAoK+yEQIgDmAgAdAAoK+yEQIgDmAgAAAA==.Darkluster:BAAANQADCgQIBAAAAA==.Darrknes:BAAANQAECgEIAQAAAA==.Darshun:BAAANQADCgUICgAAAA==.Davinah:BAABNQAECn8kAAIRAAoK3A1qXgCeAQARAAoK3A1qXgCeAQAAAA==.Dayje:BAAANQADCgUICAAAAA==.Dazarn:BAAANQADCgUIBQAAAA==.',
De='Deathation:BAAANQAECgcIDwABNQAECggIFwAUAGoYAA==.Deathbcmesyu:BAAANQAECgUIDQAAAA==.Demonovest:BAABNQAECn8jAAIcAAoKqgWN0QAmAQAcAAoKqgWN0QAmAQAAAA==.Demontoarch:BAAANQAECgIIAgAAAA==.Devoutheart:BAAANQAECgEIAQABNQAECgEIAgAGAAAAAA==.',
Di='Diehappy:BAAANQAECgQIBwAAAA==.Dishonor:BAAANQADCgYIDwAAAA==.',
Do='Dommage:BAABNQAECn88AAIBAAoKrSKTFAD3AgABAAoKrSKTFAD3AgABNQAFFAcIFAAMABcgAA==.Donkyote:BAAANQADCgEIAQAAAA==.Downbadd:BAAANQABCgQIBQAAAA==.',
Dr='Druida:BAABNQAECn9BAAQFAAoKHheXEgCfAgAFAAoKHheXEgCfAgAHAAgKsg6aQAAmAQAMAAIKKgWoXwA1AAAAAA==.Drywar:BAACNQAFFH8TAAIUAAYKFhwaEgCgAQAUAAYKFhwaEgCgAQA1AAQKfy8AAhQACgpFI3Y4AOMCABQACgpFI3Y4AOMCAAAA.',
Dt='Dtinnel:BAABNQAECn8hAAIUAAoK1xCOmQDcAQAUAAoK1xCOmQDcAQABNQAFFAUIDAAeAJIcAA==.',
Dw='Dway:BAAANQADCgUICQAAAA==.',
['Dà']='Dànger:BAAANQAECgYIDAAAAA==.',
Ec='Echidna:BAAANQAECggIDQAAAA==.',
Ef='Efran:BAAANQABCgIIAgAAAA==.',
Eg='Ego:BAABNQAECn89AAIUAAoKiCHcJgClAgAUAAoKiCHcJgClAgAAAA==.',
Ei='Eisla:BAABNQAECn8kAAIJAAoK+RKQPADfAQAJAAoK+RKQPADfAQAAAA==.',
El='Elfor:BAAANQAECgQICAABNQAECgoKMQANAGoUAA==.Elpicosito:BAAANQAECggICgABNQAECgoKQQAFAB4XAA==.',
Em='Emmone:BAAANQAECgQICAAAAA==.',
Ep='Epiconx:BAAANQADCgEIAQAAAA==.',
Ex='Exacerbator:BAAANQADCgYIGAAAAA==.',
Fa='Falcon:BAAANQABCgQIBQAAAA==.Fargecia:BAAANQAECgYICQAAAA==.Farglight:BAAANQAECgEIAQAAAA==.Faunna:BAABNQAECn9EAAIHAAoK5B1SFAB5AgAHAAoK5B1SFAB5AgAAAA==.',
Fe='Feath:BAAANQADCgIIAgAAAA==.Feebeeboofae:BAABNQAECn8lAAMBAAoKPwRsJwFKAQABAAoKPwRsJwFKAQAfAAEKAABbVAAbAAAAAA==.Felaz:BAABNQAECn9RAAIBAAoKkh3SKgCUAgABAAoKkh3SKgCUAgAAAA==.Feoridor:BAAANQADCgIIAgAAAA==.Festy:BAAANQADCggIDgAAAA==.',
Fi='Fingerguns:BAACNQAFFH8GAAIdAAMKwxfbIADmAAAdAAMKwxfbIADmAAA1AAQKf00AAx0ACgoWJJcEAOsDAB0ACgoWJJcEAOsDACAABQrbBugVAM0AAAAA.Fionaa:BAAANQADCggIBwAAAA==.',
Fl='Floortank:BAABNQAECn8wAAIhAAgKUQdUZwADAQAhAAgKUQdUZwADAQAAAA==.',
Fr='Friday:BAACNQAFFH8FAAMRAAIKPRM3JACCAAARAAIKPRM3JACCAAASAAEKcwHANgA4AAA1AAQKfzcAAxEACgpNFxw9ACECABEACgpNFxw9ACECABIABgoxDdKHAP4AAAAA.Frikilatar:BAAANQAECgEIAQAAAA==.Frrank:BAACNQAFFH8TAAIUAAcKJib7BwDyAQAUAAcKJib7BwDyAQA1AAQKfz4AAhQACgrBJmMDAN4DABQACgrBJmMDAN4DAAAA.',
Ga='Galcain:BAABNQAECn8uAAMaAAoKsyObJgD9AgAaAAoKxSKbJgD9AgAiAAcKwhguMADMAQAAAA==.Garbagio:BAAANQABCggIDwAAAA==.',
Gl='Gleam:BAAANQABCgIIAgAAAA==.',
Go='Googleyes:BAAANQADCgYIEAAAAA==.Goremaul:BAAANQAECgEIAQAAAA==.Gorizarev:BAAANQAECgcIDwAAAA==.Goss:BAAANQADCgYICAAAAA==.',
Gr='Graphene:BAAANQAECgQIBAAAAA==.Greybull:BAAANQAECgQJCwAAAA==.Griffy:BAAANQADCgQIBAAAAA==.Grimseek:BAABNQAECn81AAIiAAoKMRa+GwChAQAiAAoKMRa+GwChAQABNQAFFAgIGAAbADsRAA==.Growlyr:BAABNQAECn8nAAMeAAoKCCK3GgDsAgAeAAoKCCK3GgDsAgAhAAQKUBnUbADqAAAAAA==.Grumandel:BAABNQAECn8rAAIEAAoK0hXJDwARAgAEAAoK0hXJDwARAgAAAA==.',
Ha='Hailstrike:BAABNQAECn8vAAMjAAoK8RoiFABtAgAjAAoK8RoiFABtAgAhAAEK9w1JrwA9AAAAAA==.Hakur:BAABNQAECn9GAAICAAoK/xEefwDPAQACAAoK/xEefwDPAQAAAA==.Halfpink:BAAANQAECgUIEgABNQAECgoKKwAHABYaAA==.Hammertóe:BAAANQADCggIGgAAAA==.Hanma:BAABNQAECn8uAAIeAAoKQh1AEAB+AgAeAAoKQh1AEAB+AgAAAA==.Harribel:BAABNQAECn8pAAMfAAoKEQvVGwD5AAABAAcKLgbcEwFrAQAfAAQK/g/VGwD5AAAAAA==.',
He='Heiferina:BAABNQAECn8dAAIaAAoKJQkRkgCRAQAaAAoKJQkRkgCRAQAAAA==.Helixra:BAAANQAECgUICQAAAA==.Helixstorm:BAAANQAECgIIAgAAAA==.Hellcroh:BAACNQAFFH8PAAQbAAcKbhGZAAA6AQAbAAQK2RGZAAA6AQAcAAQKFgjzIADvAAAkAAEKAAAoHgAAAAA1AAQKfxsABBsACQodH3MUAMsBABwACAqAFjl3AP0BABsABQqyHXMUAMsBACQAAwoaHUsVAOQAAAAA.Help:BAAANQADCggIFwAAAA==.',
Hi='Hiyodam:BAAANQADCgUIAwAAAA==.Hiyodaw:BAAANQADCgIIAgAAAA==.Hizzon:BAAANQAECggICwAAAA==.',
Hy='Hyperíon:BAAANQAECgEIAQAAAA==.',
Ic='Icies:BAABNQAECn8uAAIfAAoK8hJkDAD1AQAfAAoK8hJkDAD1AQAAAA==.',
Ig='Ignacia:BAAANQAFFAEIAQAAAA==.',
Il='Ilos:BAAANQAECggIEwAAAA==.',
Im='Immafrogger:BAAANQAECgYICQABNQAECgoKJgAdAPsgAA==.',
Is='Iselle:BAAANQADCgYIBgAAAA==.Ishamaël:BAAANQADCgUIBQABNQAECgkJHwASAHgXAA==.',
Ja='Jacora:BAAANQAECggICAAAAA==.Jailene:BAAANQAECggIEwAAAA==.Jalian:BAAANQADCgIIAgAAAA==.Jawny:BAAANQADCgUIBQAAAA==.',
Jc='Jclif:BAABNQAECn8zAAIBAAoKGRF3hgCbAQABAAoKGRF3hgCbAQAAAA==.',
Je='Jehannum:BAABNQAECn8oAAISAAoKhg+HfQCrAQASAAoKhg+HfQCrAQAAAA==.Jessira:BAAANQAECgUJDwAAAA==.',
Jo='Jonahheal:BAABNQAECn8XAAIDAAoKjRxCHAADAwADAAoKjRxCHAADAwABNQAFFAgIGgARAH4fAA==.Josen:BAABNQAECn8aAAIQAAcKUBfSHgDxAQAQAAcKUBfSHgDxAQAAAA==.',
Ka='Kach:BAAANQAECgIIAgAAAA==.Kaefaith:BAAANQAECgEIAQAAAA==.Kaimi:BAAANQADCgYIFwAAAA==.Kainiy:BAAANQADCgcIIQAAAA==.Kaizenn:BAAANQADCgIIAgAAAA==.Kaladjin:BAABNQAECn8uAAQOAAoKqxLsJAD9AQAOAAoKSxLsJAD9AQAPAAcKbA5dEgD/AAAlAAYKDgywLgD1AAAAAA==.Katarena:BAABNQAECn8kAAIDAAoKTwiihACNAQADAAoKTwiihACNAQAAAA==.Kathyra:BAEBNQAECn82AAMcAAkKHBV3OQCnAgAcAAkKHBV3OQCnAgAbAAEKfwLghgAhAAABNQAFFAQIBgAWAPsBAA==.Kavax:BAABNQAECn8XAAIDAAYK1BEfkABtAQADAAYK1BEfkABtAQAAAA==.',
Ke='Keel:BAAANQADCgEIAQAAAA==.Keeller:BAAANQAECgMIBAAAAA==.Keggor:BAAANQAECgEIAgAAAA==.Keleris:BAAANQADCgcIDAAAAA==.Kelorth:BAAANQADCgcIBgAAAA==.Kentyr:BAAANQADCgQIBQAAAA==.Kez:BAAANQAECgQIBAAAAA==.',
Kh='Khasket:BAAANQAECgEIAQAAAA==.',
Ki='Kinký:BAABNQAECn8/AAIUAAoKhRLEWgDuAQAUAAoKhRLEWgDuAQABNQADCgcIBwAGAAAAAA==.Kiraelis:BAABNQAECn8yAAIiAAoKGBc8GQC9AQAiAAoKGBc8GQC9AQAAAA==.',
Ko='Konvik:BAAANQADCgUIDQAAAA==.Korvoh:BAABNQAECn8tAAIgAAoKURTDCADUAQAgAAoKURTDCADUAQAAAA==.',
Kr='Kragar:BAAANQADCgIIAgAAAA==.Kredriel:BAAANQAECgEJAQAAAA==.Krinmate:BAACNQAFFH8UAAIdAAYK5xsXCAAKAgAdAAYK5xsXCAAKAgA1AAQKfzEAAx0ACgoGHWoaAAQDAB0ACgoGHWoaAAQDACAABQpTByoWAMkAAAAA.Krystn:BAAANQAECgIIAgAAAA==.',
Ku='Kumaro:BAAANQABCgYIBgAAAA==.Kuurome:BAAANQADCgMIAwABNQAFFAUIDAAeAJIcAA==.',
Kw='Kwinny:BAABNQAECn8sAAMDAAoKIx66LwCnAgADAAoKIx66LwCnAgACAAEKwQf9mAE0AAAAAA==.',
Ky='Kyloris:BAAANQAECggIAgAAAA==.Kynalin:BAAANQADCgEIAQAAAA==.Kynthria:BAAANQAECgYIDwABNQAECgoKGAABAOkeAA==.',
['Kä']='Kämik:BAABNQAECn8mAAMaAAkK3hVRfgARAgAaAAkK3hVRfgARAgAiAAEKAACZjAAyAAAAAA==.',
['Kì']='Kìn:BAAANQADCgQIBQAAAA==.',
La='Lampion:BAABNQAECn8jAAIVAAoKPgcWMQC4AQAVAAoKPgcWMQC4AQAAAA==.Landon:BAAANQADCgYIBgABNQAECgoKMAAeAFchAA==.Lasstchance:BAAANQAECgQIBgAAAA==.Latinamaddog:BAABNQAECn8wAAIcAAoKuBpXPgAcAgAcAAoKuBpXPgAcAgAAAA==.',
Le='Leijona:BAAANQAECgUIBQAAAA==.Lelathon:BAAANQAECggICgAAAA==.Lenard:BAAANQAECgYIDQAAAA==.Leröth:BAAANQAECgQIBQAAAA==.',
Li='Lieb:BAAANQADCgcIBwAAAA==.Lightstorms:BAAANQADCgcIBwAAAA==.Lijepa:BAAANQABCgEIAQAAAA==.Likeatrain:BAABNQAECn9FAAMZAAkKaA+BFgBfAQAZAAkKaA+BFgBfAQAUAAEKAABSUwEAAAAAAA==.Lilwagyu:BAAANQAECgYIBgAAAA==.Linds:BAABNQAECn8gAAIDAAoKPRSxbgDMAQADAAoKPRSxbgDMAQAAAA==.',
Lo='Lokininja:BAAANQAECgEIAgAAAA==.Lokki:BAAANQADCgYIBgAAAA==.Loofuh:BAAANQADCgYIBgAAAA==.Loopdog:BAAANQAECgQIBwAAAA==.',
Lt='Ltdanslegs:BAABNQAECn85AAIOAAoKRB6wCwCkAgAOAAoKRB6wCwCkAgAAAA==.',
Lu='Luardreu:BAAANQADCgQIBAAAAA==.Luxu:BAABNQAECn9MAAIjAAoKtyJGDgA9AwAjAAoKtyJGDgA9AwAAAA==.Luxzy:BAAANQAECgUIEAAAAA==.',
Ma='Magdog:BAAANQADCgMIBAAAAA==.Magicbarbee:BAAANQADCgYIDAAAAA==.Makarich:BAAANQAECgcIDgAAAA==.Malachron:BAABNQAECn8ZAAIcAAgKQhSpkAC9AQAcAAgKQhSpkAC9AQAAAA==.Manbearcat:BAABNQAECn8rAAMHAAoKFhpHFwBXAgAHAAoKFhpHFwBXAgAFAAIKGQTLdAA2AAAAAA==.Manzanoso:BAAANQADCggIGAAAAA==.Marbleous:BAABNQAECn8rAAIUAAgKjiANPgDRAgAUAAgKjiANPgDRAgAAAA==.Maybebeef:BAAANQAECgIIAgABNQAFFAQICgAUAGQUAA==.',
Mc='Mcpink:BAAANQADCgUICQABNQAECgoKKwAHABYaAA==.',
Me='Meatcurtains:BAAANQADCgUIBQABNQAECgoKMAAeAFchAA==.Melhina:BAAANQAECgQIBAABNQAECgoKLgAkAHEXAA==.Memisstotem:BAABNQAECn8fAAMRAAkK4QsYegCdAQARAAgKTQwYegCdAQASAAUKAhKvsgAtAQAAAA==.Merle:BAABNQAECn83AAMUAAoKxB8fLwABAwAUAAoKxB8fLwABAwATAAUKPxksGAAcAQAAAA==.',
Mi='Minaxy:BAABNQAECn9CAAICAAoK3hxyKgAdAwACAAoK3hxyKgAdAwAAAA==.Miranza:BAAANQAECgYICwAAAA==.Mistborn:BAAANQAECgcIEwABNQAECgcIFwABAMMaAA==.Mistodon:BAAANQABCgcIDwAAAA==.Mistsofpoly:BAAANQAECgQIBgABNQAFFAcIEgARAGYPAA==.Mizzon:BAAANQADCggIEQAAAA==.',
Mo='Momoku:BAABNQAECn8pAAIEAAkKWB1NCwB6AgAEAAkKWB1NCwB6AgAAAA==.Moolimbo:BAABNQAECn8dAAISAAoKqxMcOADzAQASAAoKqxMcOADzAQABNQAECgoKNwAHAMIUAA==.Mootalstrike:BAABNQAECn8bAAIUAAoKOw77swCbAQAUAAoKOw77swCbAQAAAA==.Moshworm:BAABNQAECn8pAAIHAAoK5QjyTADtAAAHAAoK5QjyTADtAAAAAA==.',
Mu='Muramasa:BAAANQAECgcIBwABNQAFFAUIDAAeAJIcAA==.',
Mv='Mvp:BAAANQADCgcIEAAAAA==.',
Na='Nadlus:BAAANQAECgUIBQAAAA==.Nalaxx:BAAANQABCgUIBQAAAA==.Namis:BAAANQAECgYICwAAAA==.',
Ne='Nelaphim:BAABNQAECn8rAAMfAAoKbByUCwAHAgAfAAoKbByUCwAHAgABAAYK2AusHQFaAQAAAA==.Neversneaky:BAABNQAECn8UAAIIAAkKBw7PYACJAQAIAAkKBw7PYACJAQABNQAECgoKLwAjAPEaAA==.Nexassin:BAAANQAECgUICQAAAA==.',
Ni='Nico:BAABNQAECn8pAAIaAAkKTB3BQgCjAgAaAAkKTB3BQgCjAgAAAA==.Nimz:BAABNQAECn8dAAQbAAgKhx4lHgB9AQAcAAgKdRXwowCNAQAbAAUK/h8lHgB9AQAkAAYKfhiGEQAfAQABNQAECgoKMAAeAFchAA==.',
No='Noxxidari:BAABNQAECn81AAIVAAoKtxzMEABOAgAVAAoKtxzMEABOAgAAAA==.Noxxus:BAABNQAECn8sAAIQAAoK1hj4DwAqAgAQAAoK1hj4DwAqAgABNQAECgoKNQAVALccAA==.',
Ny='Nymphis:BAAANQADCgQIBgAAAA==.Nymunandria:BAAANQADCgUIBQAAAA==.Nymz:BAAANQAECggIEgABNQAECgoKMAAeAFchAA==.',
Oa='Oakenshade:BAAANQADCgcICQAAAA==.',
Ob='Oblivia:BAAANQADCggIBAAAAA==.Obsidiansoul:BAAANQAECgMIAwAAAA==.',
Og='Oghma:BAAANQAECgcICAAAAA==.',
Ol='Oldmans:BAAANQADCgIIAgAAAA==.',
On='Onagne:BAAANQAECgEIAQABNQAECgoKMgAUAI4fAA==.Onepunch:BAAANQADCgcIBwAAAA==.Onezero:BAAANQADCgYICQAAAA==.',
Or='Orchist:BAABNQAECn8qAAITAAkKnB5NBACyAgATAAkKnB5NBACyAgAAAA==.Orimbo:BAABNQAECn83AAMHAAoKwhRbXABgAQAHAAcKDxBbXABgAQAFAAQKZgevXgB9AAAAAA==.',
['Oð']='Oðynn:BAAANQAECggICAABNQAECgIIAgAGAAAAAA==.',
Pa='Paidu:BAACNQAFFH8TAAQLAAcK7w3QAgCxAAANAAUKaBF3DQA2AQALAAQKwBDQAgCxAAAVAAIKkgI2EgBCAAA1AAQKfzQABAsACgocIDwGAEUCAA0ACgrVHk0oAFwCAAsACAqdHjwGAEUCABUACAqzCj00AKEBAAAA.Palaritaz:BAAANQAECgIIBAABNQAECgcIFwABAMMaAA==.',
Pe='Pestilancé:BAABNQAECn8rAAIhAAoK6QRabwDhAAAhAAoK6QRabwDhAAAAAA==.',
Ph='Phenothal:BAAANQADCgYIBgAAAA==.',
Pi='Pingpaung:BAAANQAECgQIBQAAAA==.Pinktp:BAAANQAECgIIAgAAAA==.Pion:BAAANQADCgQIBAAAAA==.Piratecass:BAAANQAECgcICgAAAA==.Pitchblende:BAABNQAECn80AAIDAAoKDROxZwDgAQADAAoKDROxZwDgAQAAAA==.',
Po='Polylock:BAAANQAECggIDwAAAA==.Portiaa:BAABNQAECn8VAAMBAAgKZwiDEQFvAQABAAcKYgeDEQFvAQAfAAIKgA1WNgBjAAAAAA==.Pothette:BAAANQAECgIIAgABNQAECgoKNAAmANEZAA==.',
Pr='Prangkim:BAAANQAECgIIAgAAAA==.Protagoras:BAAANQADCgQIBAAAAA==.',
Pu='Purejoy:BAAANQAECgQIBQAAAA==.',
Qu='Quickslice:BAAANQADCgcJBwAAAA==.Quillz:BAABNQAECn8UAAIZAAUKihUwJwDCAAAZAAUKihUwJwDCAAAAAA==.',
Ra='Rajak:BAAANQADCgMIAwAAAA==.Rathidk:BAACNQAFFH8OAAIjAAcK5hlbCgCyAQAjAAcK5hlbCgCyAQA1AAQKf1EAAiMACgqUJCgGAJIDACMACgqUJCgGAJIDAAAA.',
Re='Redine:BAAANQADCgcICgAAAA==.Reen:BAAANQADCgcICQAAAA==.Rellt:BAAANQAECgMIAwAAAA==.Rendis:BAAANQAECgQIBQAAAA==.',
Rh='Rhayge:BAABNQAECn8tAAMKAAoK5A3jGADYAQAKAAoK5A3jGADYAQARAAcKTQl80QDEAAAAAA==.',
Ri='Riemann:BAAANQABCggICwAAAA==.',
Ro='Roxas:BAAANQADCgIIAgAAAA==.',
Ru='Ruukia:BAACNQAFFH8MAAIeAAUKkhx4CADUAAAeAAUKkhx4CADUAAA1AAQKf2QAAh4ACgr8JYEHAIgDAB4ACgr8JYEHAIgDAAAA.',
['Ré']='Révölt:BAAANQAECgYIBQAAAA==.',
Sa='Saboo:BAABNQAECn8yAAIkAAoKpRaIBgBDAgAkAAoKpRaIBgBDAgAAAA==.Sahki:BAAANQADCgUIDAAAAA==.Saltybreath:BAABNQAECn8nAAIXAAkKhxWPHQD1AQAXAAkKhxWPHQD1AQABNQAECgoKOQAOAEQeAA==.Sapientia:BAABNQAECn8hAAICAAgKeAa87gA/AQACAAgKeAa87gA/AQAAAA==.Savagex:BAAANQADCgMIAwAAAA==.',
Sc='Scottkill:BAAANQADCggIDAABNQAFFAgIGAABAG0PAA==.',
Se='Seasnan:BAAANQAECgIIAQAAAA==.Segur:BAAANQABCgIIAgAAAA==.Seluna:BAAANQAECgcIEgAAAA==.Senapally:BAAANQADCgQIBAABNQAECgkJFgAaAOMXAA==.Senlock:BAAANQABCgIIAgABNQAECgkJFgAaAOMXAA==.',
Sh='Shadizzon:BAAANQADCgQIBAAAAA==.Shadowcloak:BAAANQABCgMIAwAAAA==.Shadowdeath:BAABNQAECn8qAAMhAAkKKQVJYAAkAQAhAAkKKQVJYAAkAQAeAAEK2gMDkgAoAAAAAA==.Shadowheàrt:BAAANQAECgYIEQAAAA==.Shadowshifty:BAAANQADCgcIDQAAAA==.Shadowtotem:BAAANQAECggIEQAAAA==.Shagi:BAAANQAECgUICgAAAA==.Shamdü:BAABNQAECn9DAAIUAAoKJiKnFgBfAwAUAAoKJiKnFgBfAwAAAA==.Shanson:BAAANQAECgYICwAAAA==.Sharroz:BAAANQAECgIIBAAAAA==.Shizuuku:BAAANQAECgEIAQABNQAFFAUIDAAeAJIcAA==.Shockybalboa:BAABNQAECn8XAAISAAgKZAgWmgBkAQASAAgKZAgWmgBkAQAAAA==.Showerthots:BAAANQAECgUIDwAAAA==.',
Si='Silvver:BAAANQADCgcIBwAAAA==.Sineth:BAAANQADCggIEAAAAA==.',
Sk='Skooda:BAABNQAECn83AAISAAoKLhaSMwAIAgASAAoKLhaSMwAIAgAAAA==.Skybles:BAAANQAECgUICQAAAA==.Skyded:BAAANQADCgUIBQAAAA==.Skyfell:BAABNQAECn8qAAIVAAoK8hT2JgANAgAVAAoK8hT2JgANAgAAAA==.Skyknight:BAABNQAECn8lAAITAAoKVBrlBwAwAgATAAoKVBrlBwAwAgAAAA==.',
Sl='Sloan:BAAANQADCgMIAwAAAA==.',
Sn='Snapahead:BAAANQAECgEIAQAAAA==.Sneakpeak:BAAANQADCgIIAgAAAA==.',
So='Solcon:BAABNQAECn8jAAINAAoK2xkDNQAGAgANAAoK2xkDNQAGAgAAAA==.Solence:BAAANQAECgEIAwAAAA==.Somebodie:BAAANQAECgQIBwAAAA==.',
Sp='Spaazz:BAABNQAECn8nAAICAAoKBRXVmwDrAQACAAoKBRXVmwDrAQAAAA==.Sparkwire:BAAANQADCggICAAAAA==.',
Sq='Squeakbolt:BAAANQADCgcIDwAAAA==.',
St='Starofdreams:BAAANQADCgEIAQABNQAECgoKLAAdAK8QAA==.Staroflight:BAAANQAECgEIAQABNQAECgoKLAAdAK8QAA==.Starweaver:BAABNQAECn8sAAMdAAoKrxCkTQACAgAdAAoKrxCkTQACAgAgAAEKtgFQMwAZAAAAAA==.Stormrender:BAABNQAECn84AAQOAAoKqxTUJQD1AQAOAAoKqxTUJQD1AQAlAAMKvgYoSABJAAAPAAEK+AFQLAAcAAAAAA==.Stormsong:BAACNQAFFH8FAAISAAMKuxFVGgDvAAASAAMKuxFVGgDvAAA1AAQKfxkAAxIACQqlHOE1AKACABIACQqlHOE1AKACABEAAwryCg3wAIoAAAAA.Strangecandy:BAABNQAECn8qAAIVAAkK+grMJwBbAQAVAAkK+grMJwBbAQAAAA==.Strangrdangr:BAAANQADCgQIBAAAAA==.Strángeland:BAAANQAECgIIAgAAAA==.Störmrender:BAAANQAECgEIAQABNQAECgoKOAAOAKsUAA==.',
Su='Sublïminals:BAABNQAECn9HAAQDAAoKQCVcAQAvBAADAAoKQCVcAQAvBAACAAkKKhinmQDwAQAQAAMKkCGHRQDaAAAAAA==.Suhalo:BAAANQADCgMIAwAAAA==.Sunarianna:BAABNQAECn8iAAIBAAoKiRFvYAD2AQABAAoKiRFvYAD2AQAAAA==.Sundaze:BAAANQAECgIIAgAAAA==.Superpull:BAAANQAECgUICQABNQAECgIIAgAGAAAAAA==.',
Sy='Sycla:BAABNQAECn8pAAMbAAoKMhq3GACmAQAcAAgK6hf5iwDJAQAbAAYKMBi3GACmAQAAAA==.Syedrine:BAAANQAECgQIDQAAAA==.Sylas:BAAANQAECgQICAAAAA==.',
Ta='Tab:BAAANQAECgUICwAAAA==.Taloriesh:BAABNQAECn8pAAMdAAoKYxkoLQCSAgAdAAoKYxkoLQCSAgAnAAQKqQq8QwCeAAAAAA==.Tanazir:BAEANQAECgUICwAAAA==.Tarok:BAAANQADCgUICgAAAA==.Tashien:BAAANQAECggIBwAAAA==.',
Te='Tealzin:BAAANQABCgQIBQAAAA==.Techytechy:BAAANQAECgYIBgAAAA==.Teito:BAAANQAECgcIEwABNQAECgkJIAACACEfAA==.Terenii:BAAANQAECgIIAgAAAA==.',
Ti='Tilamano:BAABNQAECn8rAAQcAAoKriTRDQBgAwAcAAoKWSTRDQBgAwAbAAgKFSMWCgBWAgAkAAYKViEGCwDAAQAAAA==.Tilatree:BAAANQAECgEIAgABNQAECgoKKwAcAK4kAA==.Tillidari:BAAANQAECgQIDgABNQAECgoKKwAcAK4kAA==.',
To='Tohrnamental:BAAANQAECgMIBAAAAA==.Tohrnarc:BAABNQAECn8nAAIBAAoKlSCqiwBoAgABAAoKlSCqiwBoAgAAAA==.Tookkiiee:BAAANQAECggICwAAAA==.Totem:BAAANQAECgQIBgAAAA==.Totemwebz:BAABNQAECn8eAAIRAAcKXh1sUgAdAgARAAcKXh1sUgAdAgAAAA==.',
Tr='Trenve:BAABNQAECn8xAAIFAAoKWR8vDwDVAgAFAAoKWR8vDwDVAgAAAA==.',
Ts='Tseirpa:BAAANQADCgQIBQAAAA==.',
Tu='Turbomage:BAAANQADCgcIBwAAAA==.Tuzzyfits:BAABNQAECn8zAAIRAAoKdxzfNgCDAgARAAoKdxzfNgCDAgAAAA==.',
Tw='Twojayzz:BAAANQAECggIEAAAAA==.',
Ty='Tyrethia:BAABNQAECn8XAAIUAAgKahgXqwCxAQAUAAgKahgXqwCxAQAAAA==.',
['Té']='Téchymoon:BAACNQAFFH8HAAIbAAMKYgODDACfAAAbAAMKYgODDACfAAA1AAQKf2wAAhsACgqYHXUBALECABsACgqYHXUBALECAAAA.',
Ug='Uggaibo:BAAANQADCgcIDgAAAA==.Ugo:BAAANQAECgQIBAAAAA==.',
Um='Umbron:BAABNQAECn8jAAQJAAkKcRk+HACcAgAJAAkKDhg+HACcAgAIAAcK9xhJHQDoAQAoAAEKMA+DHAAvAAAAAA==.',
Un='Undertaker:BAAANQABCggIDAAAAA==.',
Us='Useche:BAAANQAECgQIBAAAAA==.',
Va='Valcristo:BAABNQAECn8uAAIQAAoKcCQBDwCsAgAQAAoKcCQBDwCsAgAAAA==.Valdun:BAAANQADCgcIEQAAAA==.Vanaras:BAAANQADCgYIBwAAAA==.',
Ve='Venous:BAABNQAECn8oAAMJAAoK3RVFSQCfAQAJAAcKMBJFSQCfAQAIAAkKohGiKgBuAQAAAA==.Vestt:BAAANQADCggIFQAAAA==.',
Vi='Vicariana:BAACNQAFFH8UAAMnAAcKyh8eBgBYAQAnAAUK+x0eBgBYAQAdAAQKkgIPJAC6AAA1AAQKf0UABCcACgrhIZcKALUCACcACgrhIZcKALUCACAABgpnJJAEAH4CAB0ACQqgFvBQADECAAAA.Victhyr:BAAANQAECgUICQAAAA==.Vidette:BAAANQAECgEIAQAAAA==.Viduus:BAABNQAECn8wAAMeAAoKVyE9EgBmAgAeAAoKVyE9EgBmAgAhAAgKrxYZQgC9AQAAAA==.Viv:BAABNQAECn8xAAMCAAoKSRj9YgAMAgACAAoKSRj9YgAMAgADAAMKEyCTuwAFAQAAAA==.',
Vo='Vodmor:BAABNQAECn8qAAICAAoK7AWOyQBDAQACAAoK7AWOyQBDAQAAAA==.Voldermort:BAAANQADCgcIEwAAAA==.Voran:BAAANQADCgIIAgAAAA==.',
Wa='Warrendemon:BAAANQAFFAIIAgAAAA==.Waygun:BAAANQADCggICQAAAA==.',
We='Wedowarcrime:BAAANQADCgIIAgAAAA==.',
Wh='Whims:BAABNQAECn9dAAIbAAoKkBbGAgA5AgAbAAoKkBbGAgA5AgAAAA==.',
Wi='Wildheart:BAAANQAECgEIAgAAAA==.Windgoddess:BAAANQADCggICAAAAA==.Wingchún:BAABNQAECn8cAAIOAAgKmg+dHwCiAQAOAAgKmg+dHwCiAQAAAA==.',
Wo='Woregontail:BAAANQAECgQICAAAAA==.Wowbelly:BAABNQAECn8bAAMlAAoKdiG6CQDuAgAlAAoKdiG6CQDuAgAOAAEKpwjkXQA0AAAAAA==.',
Xa='Xalrissa:BAAANQADCgUICgAAAA==.Xandeath:BAABNQAECn8XAAQjAAgKyg6kPQBJAQAjAAcK8RCkPQBJAQAhAAMKfAPemgBdAAAeAAEKTgVX7AApAAAAAA==.Xandem:BAAANQAECgUIBAAAAA==.Xandros:BAABNQAECn8VAAIkAAcKKxBQCwC3AQAkAAcKKxBQCwC3AQAAAA==.Xanlight:BAAANQADCgIIAgAAAA==.',
Xo='Xonk:BAACNQAFFH8LAAIkAAUKcA89AgAaAQAkAAUKcA89AgAaAQA1AAQKfz8AAyQACgo1HDwEAJ8CACQACgo1HDwEAJ8CABsAAQqMG2JoAFEAAAAA.',
Yg='Ygcamel:BAAANQADCggIEgAAAA==.',
Yi='Yiazmat:BAAANQABCgcIDQAAAA==.',
Ys='Ysondrie:BAAANQAECgUIBQAAAA==.',
Za='Zaklu:BAAANQAECgIIBAAAAA==.Zalagrimbor:BAABNQAECn8fAAMSAAkKeBcKRwBaAgASAAkKeBcKRwBaAgARAAMKgAWC/wBrAAAAAA==.Zalathar:BAAANQABCgQIBAAAAA==.Zaps:BAABNQAECn8tAAISAAoKeCDQIgD9AgASAAoKeCDQIgD9AgAAAA==.Zarev:BAACNQAFFH8QAAIiAAYKchlBBgDzAQAiAAYKchlBBgDzAQA1AAQKfyoAAiIACQoAI4cNAAYDACIACQoAI4cNAAYDAAAA.',
Ze='Zeenab:BAAANQADCgIIAgAAAA==.Zegrath:BAAANQADCgcJDAABNQAECgUICgAGAAAAAA==.Zelie:BAABNQAECn8rAAMRAAoK3gu9gACKAQARAAoK3gu9gACKAQASAAUK4wDHDwFsAAAAAA==.Zenreto:BAABNQAECn8rAAIJAAoKHxWjMgATAgAJAAoKHxWjMgATAgAAAA==.',
Zh='Zhuri:BAAANQADCggIEgAAAA==.',
Zo='Zoeri:BAAANQAECgQIDQAAAA==.Zoltraak:BAAANQADCgYIDwAAAA==.',
['Än']='Änmoa:BAACNQAFFH8UAAIKAAcKrxeMAQBvAQAKAAcKrxeMAQBvAQA1AAQKf1EAAgoACgpsJbsBAJ0DAAoACgpsJbsBAJ0DAAAA.',
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
