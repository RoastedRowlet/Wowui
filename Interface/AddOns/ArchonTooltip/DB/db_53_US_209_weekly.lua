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

local lookup = {'Priest-Holy','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Druid-Guardian','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Warrior-Arms','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Hunter-BeastMastery','DeathKnight-Unholy','Shaman-Elemental','DeathKnight-Blood','Shaman-Restoration','Mage-Arcane','Shaman-Enhancement','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Mage-Frost','Paladin-Holy','Hunter-Marksmanship','Rogue-Assassination','Hunter-Survival','Paladin-Protection','Evoker-Devastation','Evoker-Preservation','Rogue-Subtlety','Monk-Brewmaster','Evoker-Augmentation','Druid-Feral',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aassvik:BAABNQAECn8eAAIBAAcK3CKgLQCvAgABAAcK3CKgLQCvAgAAAA==.',
Ab='Absolute:BAACNQAFFH8OAAICAAUKYyWEAwAcAgACAAUKYyWEAwAcAgA1AAQKfyMAAgIACQpLJDwFAH0DAAIACQpLJDwFAH0DAAAA.',
Ac='Achelin:BAAANQADCgUIBQAAAA==.Achieved:BAACNQAFFH8QAAMDAAYKwhwACQDqAQADAAYKwhwACQDqAQAEAAEK1AC3GAAwAAA1AAQKfykABAMACQozI/4LAGoDAAMACQozI/4LAGoDAAQABgp/ENM6AEQBAAUAAQoAAOtqACAAAAAA.Achievsome:BAABNQAECn8sAAQGAAkKeyWQAwCfAwAGAAkKeyWQAwCfAwABAAYK8BOThwB7AQAHAAEK0AY0KQAwAAAAAA==.',
Ad='Adorabull:BAAANQADCgQIBQAAAA==.',
Ae='Aesomx:BAAANQAECgEIAQABNQAECgQICwAIAAAAAA==.Aesoxp:BAAANQAECgIIBAABNQAECgQICwAIAAAAAA==.Aethalas:BAAANQABCgIIAgAAAA==.',
Ag='Agrajag:BAAANQADCgUIBQABNQAECgkJNgAJAAAgAA==.',
Ah='Ahnruun:BAAANQAECgQIBQAAAA==.',
Ai='Aiona:BAAANQADCgQIBAAAAA==.',
Ak='Akagrats:BAAANQADCgEIAQAAAA==.',
Al='Alassar:BAAANQAECgUICwAAAA==.Alazan:BAAANQAECgQIBAAAAA==.Alcaraz:BAAANQADCggIEwAAAA==.Alessandro:BAAANQAECgcIEQAAAA==.Aliengrey:BAAANQAECgUICAAAAA==.Allyissa:BAAANQADCgIIAgAAAA==.Alonsusfaol:BAABNQAECn8nAAIKAAkKFxX0cABJAgAKAAkKFxX0cABJAgAAAA==.Alrsta:BAAANQADCgIIAQAAAA==.Alunarteil:BAAANQAECgEIAQAAAA==.',
Am='Amane:BAABNQAECn8rAAMLAAgKLiK2BgCnAgALAAcKIyO2BgCnAgAMAAgKABVlNwDxAQAAAA==.Ammaydie:BAAANQADCgIIAgAAAA==.Amytenchi:BAAANQABCggIEgAAAA==.',
An='Anger:BAAANQADCggJDQAAAA==.Annya:BAABNQAECn8jAAMBAAgK4hWRUQArAgABAAgK4hWRUQArAgAGAAYKyQpfQgAbAQAAAA==.',
Ar='Archdragon:BAAANQADCgMIAwABNQAECgkJJAAEAN4kAA==.Archtrishop:BAAANQADCgEIAQAAAA==.Aristae:BAAANQABCgIIAgABNQAECgcIEAAIAAAAAA==.Arkanis:BAABNQAECn8qAAINAAgK+BE0CwAOAgANAAgK+BE0CwAOAgAAAA==.Armament:BAABNQAECn8oAAIJAAkKnRRrWwB2AgAJAAkKnRRrWwB2AgAAAA==.Arthus:BAAANQADCggICAAAAA==.',
As='Ashleymarion:BAAANQADCgIJAgAAAA==.',
At='Aträyu:BAAANQADCggICAAAAA==.Attlas:BAAANQADCgQIBAAAAA==.',
Au='Aurafiora:BAABNQAECn8yAAIOAAkK5yEsDgBuAwAOAAkK5yEsDgBuAwAAAA==.Aurius:BAAANQAECgcIDgAAAA==.',
Av='Avalancha:BAABNQAECn8mAAIFAAgKqxfBFAAVAgAFAAgKqxfBFAAVAgAAAA==.Avinoch:BAAANQAECgUIDAAAAA==.',
Ax='Axon:BAAANQAECggIEAAAAA==.',
Ay='Aynhillbeads:BAAANQAECgEIAQABNQAECgUIDAAIAAAAAA==.',
Az='Azekor:BAAANQADCggIEQAAAA==.Azenroth:BAAANQAECgUICAAAAA==.Azureth:BAABNQAECn8WAAIPAAgKDho/QgAPAgAPAAgKDho/QgAPAgAAAA==.',
Ba='Babykay:BAAANQADCgUICAABNQAECggILQAQAN4fAA==.Bakimono:BAAANQADCgQIBAAAAA==.Banehellborn:BAAANQAECggICwAAAA==.Barnicas:BAAANQADCgYICQABNQAECgMIAwAIAAAAAA==.Bartholomäus:BAAANQADCgUJCwAAAA==.Batmack:BAAANQABCgQIBAAAAA==.',
Bb='Bbshagoogoo:BAAANQAECgIIAgABNQAECgQIBwAIAAAAAA==.',
Be='Beezlebumon:BAABNQAECn8gAAMPAAgKbBSmTQDaAQAPAAgKThSmTQDaAQARAAEKmAm0ygAxAAAAAA==.Beld:BAAANQADCgcIBwAAAA==.Bellcross:BAAANQADCgUIBQAAAA==.Belloq:BAAANQAECgEJAQAAAA==.Benedis:BAAANQAECgMIAwAAAA==.Bené:BAAANQADCggICAAAAA==.Berend:BAAANQAECgUIBQAAAA==.Bewater:BAABNQAECn8kAAIOAAcKjBa8fgAMAgAOAAcKjBa8fgAMAgAAAA==.',
Bl='Bluberry:BAAANQADCgcIFQAAAA==.Blóðugrgríma:BAAANQAECgEIAQAAAA==.',
Bo='Bobabear:BAAANQAECgEIAQAAAA==.Bonersimpsun:BAABNQAECn8YAAIPAAgK7B8PJQCpAgAPAAgK7B8PJQCpAgAAAA==.Boombastic:BAAANQADCgYIBwAAAA==.Boomchicken:BAAANQADCgMIAwAAAA==.Boomclap:BAABNQAECn8rAAMSAAkKmhygKQC7AgASAAkKmhygKQC7AgAQAAEKAAA0NwEwAAAAAA==.',
Bp='Bpbreezy:BAACNQAFFH8NAAIBAAMKWRX6HAD1AAABAAMKWRX6HAD1AAA1AAQKfykAAwEACQobHdkcAPwCAAEACQobHdkcAPwCAAYAAwrdE7NPAM8AAAAA.',
Br='Bracknor:BAABNQAECn8dAAIOAAgKKhFxegAWAgAOAAgKKhFxegAWAgAAAA==.Brakdread:BAAANQADCgEIAQAAAA==.Braknight:BAAANQADCgYIBgAAAA==.Brandonb:BAABNQAECn84AAITAAkKpiJEHwBcAwATAAkKpiJEHwBcAwAAAA==.Brandonresha:BAAANQAECgEIAQAAAA==.Brandonw:BAAANQAECgUIDQAAAA==.Bredock:BAAANQAECgUICQABNQAFFAYIEAAOAL8XAA==.Brittlehorn:BAAANQADCgYIBgAAAA==.Brotem:BAABNQAECn8ZAAIUAAkKlBnFCwCyAgAUAAkKlBnFCwCyAgAAAA==.Brucejenner:BAAANQAECggICAAAAA==.Brutalisto:BAAANQAECgYICQAAAA==.Bryanthesly:BAAANQADCggIFAAAAA==.Brynnbramble:BAAANQADCgcIDgAAAA==.',
By='Bysokar:BAABNQAECn8eAAIVAAkKdxreFACrAgAVAAkKdxreFACrAgAAAA==.',
Ca='Cainfortea:BAAANQAECgEIAgAAAA==.Cakel:BAAANQADCgcIBwAAAA==.Calipal:BAAANQAECgQIBAAAAA==.Calipriest:BAAANQADCgQIAgAAAA==.Calisha:BAAANQADCgQIBAAAAA==.Catalinaholy:BAAANQAECggIDgABNQAFFAUKCAASAPESAA==.Catalinasham:BAACNQAFFH8IAAISAAUK8RLmDQBpAQASAAUK8RLmDQBpAQA1AAQKfxwAAhIACQrRIpwXABQDABIACQrRIpwXABQDAAE1AAUUBQoIABIA8RIA.Cataster:BAAANQADCgcIAwAAAA==.Cazadore:BAAANQADCggIDwAAAA==.',
Ce='Celardron:BAAANQAECgMIAwAAAA==.Celebrimbjor:BAAANQAECgEIAQAAAA==.Cerberusbone:BAAANQAECgUIEAAAAA==.',
Ch='Challengerz:BAAANQAECgUIDQAAAA==.Charliehorse:BAAANQADCgQIBAAAAA==.Chopper:BAAANQAECgYIDgAAAA==.',
Ci='Cinderlily:BAAANQAECgUICgAAAA==.',
Cl='Clayprincess:BAAANQADCgYICAABNQAECggIDAAIAAAAAA==.',
Co='Conflagrate:BAACNQAFFH8LAAMWAAQKZBkAGAA6AQAWAAQKmxUAGAA6AQAXAAEK5hQcGgBRAAA1AAQKfx8ABBYACQr7IEMZACADABYACQr7IEMZACADABgAAQoAAEQnAE0AABcAAQprGopqAEoAAAAA.Connery:BAAANQADCgYIFwAAAA==.Cornpopp:BAAANQADCgYIDgAAAA==.Coryuchiha:BAAANQADCgEIAQAAAA==.',
Cp='Cptcrushingb:BAAANQADCggIEAAAAA==.',
Cr='Crax:BAAANQADCgMIBAAAAA==.Crithappens:BAAANQAECgMIBAAAAA==.Criturrpants:BAAANQAECggICwAAAA==.Crouch:BAAANQAECgIIAgAAAA==.',
Cy='Cynnå:BAABNQAECn8dAAITAAkKlRjPVwDQAgATAAkKlRjPVwDQAgAAAA==.Cynthea:BAAANQADCgMJAwAAAA==.Cyp:BAABNQAECn8rAAIJAAkKAxiLZgBYAgAJAAkKAxiLZgBYAgAAAA==.',
['Cü']='Cüpcake:BAAANQAECgcIDgAAAA==.',
Da='Dababycar:BAAANQAECgYIDAAAAA==.Dabbyduck:BAABNQAECn8iAAMWAAkK7BloMwC5AgAWAAkK7BloMwC5AgAXAAcKLg74GACjAQAAAA==.Dambalah:BAAANQAECgEIAQAAAA==.Damsure:BAAANQAECgQIBAAAAA==.Danifru:BAAANQAECgYIBwAAAA==.Darren:BAAANQABCggIEgAAAA==.',
De='Deadincide:BAEBNQAECn8fAAIPAAgKXxVcQQAUAgAPAAgKXxVcQQAUAgAAAA==.Deadstasheo:BAACNQAFFH8JAAIPAAMKNB/EDgAcAQAPAAMKNB/EDgAcAQA1AAQKfyQAAg8ACQoPI00YAPoCAA8ACQoPI00YAPoCAAAA.Deathblight:BAAANQADCgYIBAAAAA==.Decree:BAABNQAECn8aAAIKAAgKuxVAfQArAgAKAAgKuxVAfQArAgAAAA==.Deezmonz:BAAANQAECgUICgABNQAECgkJNgAJAAAgAA==.Delik:BAABNQAECn8mAAIZAAgKkhZcCQA7AgAZAAgKkhZcCQA7AgAAAA==.Deluded:BAAANQAECggICQAAAA==.Demonarch:BAAANQADCgYICgAAAA==.Demonlordmeh:BAAANQADCgUICQAAAA==.Demïse:BAAANQADCgcICQAAAA==.Dendrite:BAAANQAECgMIAwAAAA==.Deneol:BAABNQAECn8gAAMGAAkKIRryEADpAgAGAAkKIRryEADpAgAHAAEK3BFNJwA3AAAAAA==.Destrogen:BAABNQAECn8XAAQYAAgKxheOCwCvAQAYAAcKThqOCwCvAQAWAAQKjQs/8wDfAAAXAAIKow2FWwBuAAAAAA==.Desìre:BAABNQAECn8lAAIHAAgK+R4rAwDIAgAHAAgK+R4rAwDIAgAAAA==.Deäthgär:BAAANQADCgMIAwABNQAECggIFwAaAC0KAA==.',
Di='Diabolic:BAAANQADCggICAAAAA==.Dirty:BAAANQADCggIGQAAAA==.Discotheque:BAAANQADCgMIAwAAAA==.',
Dk='Dksura:BAABNQAECn8kAAIPAAkKSBy7HQDXAgAPAAkKSBy7HQDXAgAAAA==.',
Do='Doomknight:BAAANQADCgcIFAAAAA==.Doomshield:BAAANQAECgQIBQAAAA==.Doomshroud:BAAANQABCgUIBQABNQAECgUICQAIAAAAAA==.Doomwing:BAAANQADCgYJBgAAAA==.',
Dr='Dracodeez:BAAANQAECgUICAAAAA==.Driretlan:BAAANQADCgYIBwAAAA==.Druss:BAABNQAECn8hAAMPAAkKvR9hDgBDAwAPAAkKvR9hDgBDAwARAAQKZBfljQDIAAAAAA==.',
Du='Dumbledog:BAAANQABCgQIBAAAAA==.Durunk:BAAANQAECgQICgAAAA==.',
Dz='Dzimps:BAAANQAECgMIAwAAAA==.',
['Dë']='Dëlètêd:BAAANQAECggIEAAAAA==.',
['Dì']='Dìesèl:BAAANQAECggICAABNQAECggIEAAIAAAAAA==.',
Ei='Eileen:BAAANQABCgIIBQAAAA==.',
El='Elemeesel:BAAANQADCggJCAAAAA==.Eleroeda:BAAANQADCgcIBwAAAA==.Elvessuck:BAAANQABCggIEQAAAA==.',
Em='Emilianaluz:BAAANQADCgYIGQAAAA==.',
En='Endeavor:BAAANQAECgQIBwAAAA==.',
Eq='Equâs:BAAANQADCgcIDAABNQAECgMIBgAIAAAAAA==.',
Er='Eradion:BAAANQADCggIDQAAAA==.Eredarlord:BAAANQAECgcICwAAAA==.Erelm:BAAANQAECgcIEQAAAA==.Erisson:BAABNQAECn8bAAIOAAcKoRHWmgDNAQAOAAcKoRHWmgDNAQAAAA==.Errorèdivina:BAAANQAECgQIAgABNQAECggKIwAbACALAA==.',
Es='Eszran:BAAANQAECgcICwAAAA==.',
Eu='Euthanized:BAAANQAECgIIBgAAAA==.',
Fa='Fasani:BAAANQABCgcICQAAAA==.',
Fe='Felviiv:BAAANQAECgYICAAAAA==.Fennar:BAAANQAECgIIBQAAAA==.Ferosha:BAABNQAECn8yAAIRAAkKyB4WEgAaAwARAAkKyB4WEgAaAwABNQAECgMIAwAIAAAAAA==.Fexxyr:BAAANQAECgQIBAABNQAFFAUIDgAGANIQAA==.',
Fi='Fiadh:BAAANQADCgQIBAAAAA==.Fiendishtwin:BAAANQADCgMIAwAAAA==.Firm:BAAANQADCgUICgAAAA==.Firstfear:BAAANQADCgYICwAAAA==.Fisch:BAAANQAECgUICAAAAA==.Fischglizzy:BAAANQADCgYIBgAAAA==.',
Fl='Flemtok:BAAANQAECggIAQAAAA==.Flidd:BAAANQAECgUIBgAAAA==.Flipingtiska:BAAANQAECgEIAQAAAA==.Floisa:BAAANQADCgQIBAAAAA==.Flynae:BAAANQAECggIEgAAAA==.',
Fo='Fontingaul:BAAANQAECgUICQAAAA==.',
Fr='Fragtastic:BAABNQAECn8xAAMbAAkKURqNLgDVAQAbAAcKIBWNLgDVAQAOAAUKJR1UswCZAQAAAA==.Frearyne:BAABNQAECn8kAAIEAAkK3iRJAgCpAwAEAAkK3iRJAgCpAwAAAA==.Frinu:BAAANQAECgMIBAABNQABCgIIAgAIAAAAAA==.Frogs:BAAANQADCggIJwAAAA==.Frostyshadow:BAABNQAECn8rAAITAAkKESE1HABmAwATAAkKESE1HABmAwAAAA==.Frozatresh:BAAANQAECgEJAQAAAA==.',
Fs='Fstingnemo:BAABNQAECn8hAAIVAAkKzBWrIgAPAgAVAAkKzBWrIgAPAgAAAA==.',
Fy='Fyxxie:BAACNQAFFH8OAAIGAAUK0hCvCAB8AQAGAAUK0hCvCAB8AQA1AAQKfyoAAwYACQqQHDAVALUCAAYACQqQHDAVALUCAAcAAQrYHhQhAFgAAAAA.',
Ga='Gaucho:BAAANQABCgIIAgAAAA==.',
Ge='Genvissa:BAABNQAECn8WAAIWAAkKRxGJagAaAgAWAAkKRxGJagAaAgAAAA==.',
Gi='Gialiana:BAABNQAECn8bAAIbAAgK2BO4KwDqAQAbAAgK2BO4KwDqAQAAAA==.Githryn:BAAANQABCgcIBwAAAA==.',
Gl='Glorpschlorp:BAAANQAECgcIBwABNQAFFAUIDgACAGMlAA==.',
Go='Goobby:BAAANQADCgcIDAAAAA==.',
Gr='Grassfed:BAAANQAECgcIEwAAAA==.Greenymeany:BAABNQAECn8aAAINAAUKfSNWDAD0AQANAAUKfSNWDAD0AQAAAA==.Grizzlethorn:BAAANQAECgEIAQABNQAECgcIEQAIAAAAAA==.Grully:BAABNQAECn8cAAISAAkKHA3xZQDXAQASAAkKHA3xZQDXAQAAAA==.',
Gu='Gurt:BAAANQAECgMIAwAAAA==.Guzzug:BAABNQAECn82AAIJAAkKACCrLQAEAwAJAAkKACCrLQAEAwAAAA==.',
Gw='Gwumpy:BAAANQAECgEIAgAAAA==.',
Ha='Haggard:BAABNQAECn8iAAICAAgKRxohGgCGAgACAAgKRxohGgCGAgAAAA==.Hailsbelle:BAAANQAECgcIDgAAAA==.Hashtag:BAAANQADCgUIEQAAAA==.',
Hb='Hbic:BAAANQAECgUIBgAAAA==.',
He='Healyboar:BAAANQADCgUIBQAAAA==.Heartstabber:BAABNQAECn8uAAIcAAgKRRbELAAvAgAcAAgKRRbELAAvAgAAAA==.Helado:BAAANQAECgQICAAAAA==.Hellbane:BAAANQADCgYIBgAAAA==.',
Hi='Highwayman:BAAANQAECgUICgABNQAECgkJOAAOAF8jAA==.',
Ho='Holyling:BAAANQADCgYIBgAAAA==.Holys:BAAANQADCggIBgAAAA==.Hondurasman:BAAANQADCgEIAQAAAA==.Honkhonk:BAAANQAECgUIDAAAAA==.',
Hr='Hraktar:BAAANQADCgEIAQAAAA==.',
Ic='Icwiener:BAAANQAECgUIDAAAAA==.',
Ie='Ieva:BAAANQADCgYIDAAAAA==.Ievil:BAABNQAECn8ZAAMPAAgK8wuSZAB6AQAPAAgK8wuSZAB6AQARAAEKAAAx2wAhAAAAAA==.',
Ik='Ikasha:BAAANQAECgYIBgAAAA==.',
Il='Ilyss:BAAANQAECgYIBgABNQAECgkJNgAMAAEkAA==.',
Im='Imjustpika:BAACNQAFFH8OAAIdAAYK5xBVAAAdAgAdAAYK5xBVAAAdAgA1AAQKfyEAAh0ACQpGGvYEAH8CAB0ACQpGGvYEAH8CAAAA.',
In='Inawee:BAABNQAECn84AAIEAAkK/R2hDgDmAgAEAAkK/R2hDgDmAgAAAA==.Inferniö:BAACNQAFFH8PAAITAAYK4xyGCAA4AgATAAYK4xyGCAA4AgA1AAQKfzQAAhMACQqZJIAPAJUDABMACQqZJIAPAJUDAAAA.Inkurushio:BAAANQAECgIIBAAAAA==.',
Io='Iolanie:BAAANQADCggICAAAAA==.',
Is='Ismat:BAABNQAECn84AAISAAkKng0MawDHAQASAAkKng0MawDHAQAAAA==.',
Ja='Jaeza:BAAANQADCggIJwABNQAECgYICgAIAAAAAA==.Jaqu:BAAANQAECgEIAQAAAA==.Jarshh:BAAANQAECgUICAAAAA==.',
Jo='Jonald:BAAANQAECgUIBQAAAA==.Jorrick:BAAANQAECgEIAgAAAA==.',
Ju='Judge:BAABNQAECn8XAAQeAAYKciFoGgAbAgAeAAYKciFoGgAbAgAaAAMKSwTY+gCBAAAKAAIKjw1DcQFmAAABNQAECgMIAwAIAAAAAA==.Juura:BAAANQAECgcIEgAAAA==.',
Ka='Kaedra:BAAANQADCggICAAAAA==.Kalukaynas:BAABNQAECn8UAAIaAAcK/hf+XAD/AQAaAAcK/hf+XAD/AQAAAA==.Karrog:BAAANQABCgQIBAAAAA==.Karsen:BAAANQAECgcIDQAAAA==.Kassian:BAAANQABCgIIAgAAAA==.Kaveros:BAAANQAECgYIDgAAAA==.',
Ke='Kelaan:BAAANQAECgcIEQABNQAECgcIEgAIAAAAAA==.Kelimao:BAAANQAECgUICAAAAA==.Kendrà:BAAANQADCgIIAgAAAA==.Kevron:BAAANQAECgQIBgAAAA==.',
Ki='Kiimagi:BAAANQADCgEIAQAAAA==.Killingame:BAAANQABCgEIAQAAAA==.Kiritos:BAAANQAECgcIEQAAAA==.Kiserys:BAABNQAECn8WAAMfAAcKJhD1GQCnAQAfAAcKJhD1GQCnAQAgAAQK/xFqNQDlAAAAAA==.',
Ko='Koharu:BAAANQABCgcICgAAAA==.Kollia:BAAANQADCgEIAgAAAA==.Korena:BAAANQADCgUIBwAAAA==.Kostard:BAAANQAECgEIAQAAAA==.',
Kr='Krysto:BAABNQAECn8jAAIOAAgKZgoBjgDqAQAOAAgKZgoBjgDqAQAAAA==.',
Ku='Kukulkan:BAAANQADCgQIBAAAAA==.Kurlabji:BAAANQADCgUIBQAAAA==.',
Kw='Kwatli:BAAANQADCgYIBgAAAA==.',
La='Lanaela:BAAANQABCgIIBwAAAA==.Laquisha:BAAANQADCggIDgAAAA==.Latchless:BAAANQAECgIIAgAAAA==.',
Le='Lenin:BAAANQAECgQIBQAAAA==.',
Li='Lightmasta:BAAANQADCgYIBgAAAA==.Liily:BAAANQADCggIDAAAAA==.Likdiso:BAAANQADCgcIBwAAAA==.Lillath:BAAANQABCgQIBAAAAA==.Lilydari:BAAANQADCgEIAQAAAA==.Lizzmo:BAAANQABCgQIBAAAAA==.',
Lo='Lookforlight:BAABNQAECn9FAAMKAAkKtyGfHgBHAwAKAAkKtyGfHgBHAwAeAAEK+iN8XQBgAAAAAA==.Lorenth:BAAANQAECgUICAAAAA==.',
Lu='Lucid:BAAANQAECgUICwAAAA==.Luckyjade:BAAANQAECgMIBgAAAA==.',
['Lì']='Lìte:BAABNQAECn8cAAICAAcKkA4+NQCUAQACAAcKkA4+NQCUAQAAAA==.',
Ma='Mabi:BAAANQADCgUIBQAAAA==.Macarthur:BAABNQAECn8qAAIhAAgKywkjHwDUAQAhAAgKywkjHwDUAQAAAA==.Madcowburger:BAAANQADCgYICwAAAA==.Mageyoulookk:BAAANQADCgIIAgAAAA==.Maizuko:BAAANQADCgUIBQABNQAECgkJHAARAO0bAA==.Malagu:BAAANQAECgIIBAABNQAECgkJKwATABEhAA==.Malidros:BAAANQAECgQIBAABNQAECgUIBQAIAAAAAA==.Malign:BAAANQAECggIEwABNQAFFAUIDgACAGMlAA==.Manhatten:BAAANQAECgQIBQAAAA==.Manogawd:BAAANQADCgQIBAAAAA==.Marhault:BAABNQAECn84AAMOAAkKXyM/BwCiAwAOAAkKSyM/BwCiAwAdAAUKbR8zCwBFAQAAAA==.Maria:BAAANQAECgEIAQAAAA==.Marriage:BAAANQADCgcIBwAAAA==.Masitaka:BAABNQAECn8cAAIRAAkK7RtrJACUAgARAAkK7RtrJACUAgAAAA==.Matt:BAAANQABCgQIBQAAAA==.Maxicat:BAAANQAECgMIBAAAAA==.Maximus:BAABNQAECn8aAAIKAAYKbxEf1QBqAQAKAAYKbxEf1QBqAQAAAA==.Mazah:BAABNQAECn84AAMQAAkK2BfMNgCZAgAQAAkK2BfMNgCZAgASAAIKlQIDCQFQAAAAAA==.Mazlo:BAABNQAECn8wAAMZAAkKGR4JBAD1AgAZAAkKGR4JBAD1AgATAAIK6wDOvwE4AAAAAA==.',
Me='Meibao:BAAANQAECgMIAwAAAA==.Meleebrain:BAAANQABCgEJAQABNQAECgkJNgAJAAAgAA==.Mellethir:BAABNQAECn8rAAITAAgKNQsK5AC+AQATAAgKNQsK5AC+AQAAAA==.Messalina:BAAANQAECgUIBQAAAA==.Mex:BAAANQADCggIDAAAAA==.',
Mi='Millîe:BAAANQAECgIIAwAAAA==.Minipimp:BAAANQADCgYIEwAAAA==.Mirajane:BAAANQADCgIIAgAAAA==.Missoxx:BAAANQAECgQIBQAAAA==.Mistbringer:BAAANQAECgUIDAAAAA==.',
Mo='Moarhots:BAAANQADCgIIAgAAAA==.Mofoasso:BAABNQAECn8cAAIOAAYK/yAecQAsAgAOAAYK/yAecQAsAgAAAA==.Moglayn:BAABNQAECn82AAIRAAkKACbhAQDWAwARAAkKACbhAQDWAwAAAA==.Monkazz:BAAANQADCgQIBAAAAA==.Monkorith:BAECNQAFFH8JAAIiAAQKWQ1ABgD5AAAiAAQKWQ1ABgD5AAA1AAQKfxsAAiIACQpOGkANACUCACIACQpOGkANACUCAAE1AAUUBggLABEABg4A.Monorìth:BAEBNQAFFH8LAAIRAAYKBg4UDgBtAQARAAYKBg4UDgBtAQAAAA==.Mortalkon:BAAANQADCgYJBgAAAA==.Mortis:BAAANQADCgIIAgAAAA==.',
Mu='Mullett:BAAANQADCgMIAwABNQAECggIKgAhAMsJAA==.',
My='Myspace:BAAANQADCgcICQAAAA==.Mystogaan:BAAANQADCgQJBQAAAA==.',
['Mã']='Mãdmåx:BAAANQABCggIEQABNQABCggIDgAIAAAAAA==.',
['Mø']='Mørbid:BAAANQADCggICAAAAA==.',
Na='Nakiki:BAAANQAECgQICQAAAA==.Nastyiam:BAABNQAECn8iAAIUAAkKRBSvDQCPAgAUAAkKRBSvDQCPAgAAAA==.',
Ne='Nerfornothin:BAAANQAECgYIEQAAAA==.Nethflap:BAABNQAECn8oAAIgAAkK6RD5GgAVAgAgAAkK6RD5GgAVAgAAAA==.Nezhi:BAAANQADCgIIAgAAAA==.',
Ni='Nialin:BAAANQADCggIHAAAAA==.Nifru:BAAANQADCgMIAwAAAA==.Niik:BAABNQAECn8mAAISAAkKJBqaMACcAgASAAkKJBqaMACcAgAAAA==.',
No='Norgahl:BAAANQADCgMIBAAAAA==.Nosferato:BAAANQADCgEIAQAAAA==.',
Nu='Nutmilker:BAABNQAECn8oAAIUAAkKNiSuAQCeAwAUAAkKNiSuAQCeAwAAAA==.',
Ny='Nyxnight:BAAANQADCgEIAQAAAA==.',
Ob='Obi:BAAANQAECgEIAQAAAA==.',
Om='Omacron:BAAANQADCgEIAQAAAA==.',
Or='Oriion:BAAANQADCgMIBQAAAA==.Orthae:BAAANQADCggIGQABNQAECgYICgAIAAAAAA==.',
Os='Osanyin:BAAANQADCgQIBAABNQAECgUIBQAIAAAAAA==.',
Ou='Outstanding:BAAANQADCgYIDAABNQAECgcIHgABANwiAA==.',
Oz='Ozzyzomborne:BAAANQADCggIDgAAAA==.',
Pa='Pandoosevelt:BAAANQADCgMIAwAAAA==.',
Pe='Pepis:BAAANQAECgMIBgAAAA==.',
Ph='Phemera:BAAANQADCgMIAwAAAA==.Philidan:BAAANQAECgUICQAAAA==.Phyrra:BAAANQADCgEIAQAAAA==.',
Pi='Picklerickz:BAAANQAECgIIAgAAAA==.Pikagosa:BAAANQABCgEIAQABNQAFFAYIDgAdAOcQAA==.Pilgor:BAAANQAECgYIDQAAAA==.Pirlivewire:BAAANQABCgQIBAABNQABCgQIBAAIAAAAAA==.',
Pl='Plagué:BAAANQAECgEIAQAAAA==.',
Po='Pohaku:BAAANQAECgQIBwAAAA==.Polkovnik:BAABNQAECn8fAAIJAAkKVRtwZABeAgAJAAkKVRtwZABeAgAAAA==.Powderjinx:BAAANQADCgQIBQAAAA==.',
Pr='Pravaat:BAAANQAECgYIDgAAAA==.Prayvus:BAAANQADCgIIAgAAAA==.Preroll:BAAANQADCgEIAQAAAA==.Prisonsoul:BAAANQADCgcIDQAAAA==.',
Py='Pylon:BAAANQADCgUICAAAAA==.',
Qu='Qubit:BAEANQAECgUIDQABNQAECggIHwAPAF8VAA==.Quiniustius:BAAANQAECgQIBAAAAA==.',
Ra='Rallyn:BAAANQADCggICAAAAA==.Rast:BAAANQAECgQICgAAAA==.Rastabout:BAAANQADCggICwABNQAECggILQAQAN4fAA==.Ravel:BAAANQAECgUICAAAAA==.',
Re='Reahla:BAAANQADCgcIBwAAAA==.Reclaim:BAABNQAECn8tAAIQAAgK3h/hJwDgAgAQAAgK3h/hJwDgAgAAAA==.Reios:BAABNQAECn8lAAIWAAgKrRvjQACMAgAWAAgKrRvjQACMAgAAAA==.',
Rh='Rhaego:BAAANQAECgUIBQAAAA==.Rhaz:BAABNQAECn8eAAMaAAcKSQwiiwB3AQAaAAcKSQwiiwB3AQAKAAEKAACitgEqAAAAAA==.Rhikre:BAAANQADCgUIBQAAAA==.Rhoup:BAAANQADCgcIBgABNQAECggIFwAdACcaAA==.',
Ri='Rickyspanish:BAABNQAECn8rAAICAAgK9yFFDQAOAwACAAgK9yFFDQAOAwAAAA==.Rifter:BAAANQAECgIIAgAAAA==.Rikkibobbi:BAAANQADCgMIAwABNQADCgYIBgAIAAAAAA==.Ripnmaim:BAEANQADCgYIBgABNQAECggIHwAPAF8VAA==.Rivensong:BAAANQAECgYICwAAAA==.',
Ro='Romeric:BAAANQADCggIDgAAAA==.Rontastico:BAAANQADCgIIAgAAAA==.Roupert:BAABNQAECn8XAAIdAAgKJxquBQBXAgAdAAgKJxquBQBXAgAAAA==.',
Ru='Rubyouraw:BAAANQAECgYICgAAAA==.Ruffneck:BAABNQAECn8gAAIOAAgKqROhZgBFAgAOAAgKqROhZgBFAgAAAA==.Russk:BAAANQAECgQIBQAAAA==.',
['Rû']='Rûsko:BAAANQADCgYICwAAAA==.',
Sa='Saelaan:BAAANQAECgcIEgAAAA==.Sailfu:BAACNQAFFH8QAAIVAAYKYB4nAwA3AgAVAAYKYB4nAwA3AgA1AAQKfyoAAhUACQqoJKMFAHQDABUACQqoJKMFAHQDAAE1AAUUBQgOAAIAYyUA.Saiyurie:BAAANQABCgIIAgAAAA==.Sakrine:BAAANQAECgEIAQAAAA==.Salami:BAAANQADCgcIDgAAAA==.Samo:BAABNQAECn8cAAIGAAcKpB6OHQBSAgAGAAcKpB6OHQBSAgAAAA==.Sandarr:BAABNQAECn8ZAAIeAAcK+Rg5IgDNAQAeAAcK+Rg5IgDNAQAAAA==.Sanguinne:BAAANQAECgUICwAAAA==.Santhus:BAAANQAECgUICQAAAA==.Saretae:BAAANQADCggIHQABNQAFFAYIDwATAOMcAA==.Sargemarge:BAABNQAECn8dAAISAAkKICP3DABXAwASAAkKICP3DABXAwAAAA==.',
Sc='Sci:BAABNQAECn8tAAIaAAgKGyXUDwBLAwAaAAgKGyXUDwBLAwAAAA==.',
Se='Seafoame:BAAANQADCggICAAAAA==.Selener:BAAANQAECgUICgAAAA==.Serrata:BAAANQAECgYICwAAAA==.Seymorweiner:BAAANQADCgQIBQAAAA==.',
Sh='Shaanks:BAAANQADCgYICgAAAA==.Shadowplay:BAEANQADCggIEQABNQAECggIHwAPAF8VAA==.Shamski:BAAANQAECgEJAQABNQAECgUICQAIAAAAAA==.Shamydavisjr:BAAANQABCggIDgAAAA==.Shankles:BAAANQADCgIJAgAAAA==.Shareen:BAAANQAECgMIBAAAAA==.Shathice:BAAANQADCgIIAgABNQAECgcIFAAaAP4XAA==.Shiftyfrogs:BAAANQADCgIIAgAAAA==.Shkar:BAAANQAECgEIAQAAAA==.',
Si='Sidelvar:BAAANQABCggIDQAAAA==.Silandros:BAAANQAECgIIAgAAAA==.Silther:BAAANQAECgUICAAAAA==.',
Sk='Skarath:BAAANQAECgQIEQAAAA==.',
Sl='Slavka:BAAANQADCgQIBgAAAA==.',
Sm='Smaalls:BAAANQAECgEIAQAAAA==.Smote:BAAANQADCggICwAAAA==.',
Sn='Snâppy:BAABNQAECn8cAAIEAAcKdA1qOABVAQAEAAcKdA1qOABVAQAAAA==.',
So='Societte:BAAANQAECgEIAQAAAA==.Soloron:BAABNQAECn8eAAISAAcK9RdfXAD3AQASAAcK9RdfXAD3AQAAAA==.Sorrowsöng:BAAANQAECgUICAAAAA==.Soulbrother:BAAANQAECggICAABNQAECggICAAIAAAAAA==.Southvik:BAAANQAECgQIBAABNQAECgcIHgABANwiAA==.',
Sp='Spamlock:BAAANQAECgMIAwABNQAFFAMIDQABAFkVAA==.Sparrhawk:BAAANQAECgMIBQAAAA==.Spiced:BAABNQAECn8dAAIDAAkKySHUDQBaAwADAAkKySHUDQBaAwAAAA==.Spiceweasel:BAAANQAECgMIAwAAAA==.Spirithaeler:BAAANQABCgIIAgAAAA==.Spood:BAABNQAECn8fAAMGAAkKGgyMJwDqAQAGAAkKGgyMJwDqAQAHAAUKkRPfDgA8AQAAAA==.',
St='Stabulóus:BAAANQADCggIAQAAAA==.Starskream:BAAANQADCgQIBAAAAA==.Steelarrow:BAAANQADCgUIBQAAAA==.Steliokontos:BAAANQABCgIIAgAAAA==.Stickes:BAAANQAECgQIBAAAAA==.Stingella:BAAANQADCgUIBwAAAA==.Stormclaw:BAAANQADCggIDgABNQAECgkJFgAWAEcRAA==.Stormfall:BAAANQADCgYIEQAAAA==.Streea:BAAANQADCgcIEwABNQAECgYICgAIAAAAAA==.Sttriker:BAABNQAECn8UAAIMAAgKnANTZgDbAAAMAAgKnANTZgDbAAAAAA==.Styx:BAAANQABCgQIBAABNQADCgIIAgAIAAAAAA==.',
Sy='Synsairis:BAAANQAECgUICAAAAA==.',
Ta='Talenelat:BAAANQAECgEIAQAAAA==.Talonknight:BAABNQAECn8cAAMjAAcKGAyAEQAaAQAjAAYKrA2AEQAaAQAfAAUK1QZeKQDdAAAAAA==.Tau:BAAANQAECggIDwAAAA==.Taurrows:BAAANQABCggIGwAAAA==.Tavaran:BAAANQABCgUIBgAAAA==.Tavinz:BAAANQAECgIIAwAAAA==.',
Th='Thaendofyou:BAAANQAECgYICQAAAA==.Thalonis:BAAANQABCgYIBgAAAA==.Theladyheir:BAAANQAECgEJAQAAAA==.Thelas:BAAANQAECgMIBgAAAA==.Themonk:BAAANQADCggICgABNQAECggIJgARAKgVAA==.Therise:BAABNQAECn8ZAAILAAcKsg+hFABeAQALAAcKsg+hFABeAQABNQAECgkJOAAQANgXAA==.Thetank:BAABNQAECn8mAAIRAAgKqBXOQQDzAQARAAgKqBXOQQDzAQAAAA==.Thoroughbred:BAAANQADCgYICwAAAA==.Throwdini:BAABNQAECn8iAAIOAAcK/BGgiwDvAQAOAAcK/BGgiwDvAQAAAA==.Thunder:BAAANQABCgIIAgABNQABCgQIBAAIAAAAAA==.Thunderegg:BAAANQAECgUICgABNQAECgkJOAAQANgXAA==.Thundermaker:BAAANQAECgQIBAABNQAECgkJIQAPAL0fAA==.',
Ti='Timotthy:BAABNQAECn8ZAAQFAAcKcSDiEgAvAgAFAAYKPiDiEgAvAgAkAAUKmQ0xHQAxAQADAAEKAAA+yAAXAAAAAA==.Tixxle:BAAANQADCggIFgAAAA==.',
Tm='Tmate:BAAANQADCgQIBAAAAA==.',
To='Totemaka:BAAANQADCgUIBQAAAA==.Touchmé:BAAANQADCgQIBAAAAA==.Tousle:BAAANQAECgYIBgABNQAFFAQICwAWAGQZAA==.',
Tr='Treateak:BAAANQADCgYIBgAAAA==.Treb:BAAANQADCggICAAAAA==.Trotsky:BAAANQAECggIEwAAAA==.Trögdor:BAAANQADCgUIBQAAAA==.',
Tu='Tulanis:BAABNQAECn83AAIbAAkKtRvDEADgAgAbAAkKtRvDEADgAgAAAA==.Turbotax:BAAANQADCgEIAQAAAA==.',
Tw='Twerker:BAAANQADCgYIBgAAAA==.',
Ty='Tyfa:BAAANQAECgcIDgAAAA==.Tyriem:BAABNQAECn8eAAIOAAkKEhYePwCrAgAOAAkKEhYePwCrAgAAAA==.Tyssanton:BAABNQAECn8eAAMfAAgKRwNQIwAnAQAfAAgKRwNQIwAnAQAgAAcK4gPWMAARAQAAAA==.',
Tz='Tziganin:BAAANQAECgUICAAAAA==.',
Ug='Uggork:BAAANQADCgQIBwABNQAECgcIFAAaAP4XAA==.',
Un='Unholybussy:BAAANQAECgUIBwAAAA==.',
Ut='Utaadh:BAABNQAECn8jAAIMAAgKwhK6NgD1AQAMAAgKwhK6NgD1AQAAAA==.',
Va='Vael:BAAANQAECgUIDgABNQAECgkJNgAMAAEkAA==.Vaelhorn:BAAANQAECgMIAwABNQAECgcIEQAIAAAAAA==.Vallderossa:BAAANQADCgYIBgAAAA==.Vallerin:BAABNQAECn8dAAIUAAcKhBQPFAAkAgAUAAcKhBQPFAAkAgAAAA==.',
Ve='Velaar:BAAANQAECgIIAgABNQAECgkJNgAMAAEkAA==.Velazar:BAAANQADCgMIAwAAAA==.',
Vi='Vicenti:BAAANQADCgYIEQAAAA==.Victory:BAAANQADCgYIBgAAAA==.Vikthyr:BAAANQADCgUIBgABNQAECgcIHgABANwiAA==.Vikzul:BAAANQADCgEIAQAAAA==.Virginslyer:BAAANQAECgMIAwAAAA==.',
Vo='Vodnar:BAACNQAFFH8QAAIOAAYKvxfdBAAGAgAOAAYKvxfdBAAGAgA1AAQKfygABA4ACQoXINkvANsCAA4ACQoXINkvANsCABsAAQpBGMV/AEEAAB0AAQoAADETADUAAAAA.',
Vu='Vulnixia:BAABNQAECn8kAAIRAAgKYRuCLABjAgARAAgKYRuCLABjAgAAAA==.',
Wa='Wagwan:BAAANQAECgQICwAAAA==.Walls:BAAANQAECgcIEAAAAA==.Wardrik:BAAANQADCgUJBQAAAA==.Waste:BAAANQAECgUICAAAAA==.Wawel:BAABNQAECn8eAAQfAAkKvhusDgBxAgAfAAgKLRqsDgBxAgAgAAUKVSCdIQC+AQAjAAQKAxkEFADrAAAAAA==.Wazwaz:BAAANQAECgEIAQABNQAECggILQAaABslAA==.',
Wi='Wildbill:BAAANQAECgIIAwAAAA==.Willîe:BAAANQAECgMICAAAAA==.Wingsofsteel:BAAANQABCgQIBAAAAA==.Winstagram:BAAANQADCgQIBAAAAA==.',
Wo='Wolnir:BAAANQADCgUICQAAAA==.Wombshifter:BAAANQAECgEIAQAAAA==.Wowiezonk:BAAANQABCgIIAgAAAA==.',
Xe='Xeracia:BAAANQADCggIDgAAAA==.Xerethis:BAAANQADCgcIDAAAAA==.',
Xs='Xshirroz:BAAANQADCggICAAAAA==.',
Yn='Yn:BAAANQABCgQIBgAAAA==.',
Yo='Yogí:BAABNQAECn8sAAIUAAgK/xh3DwBwAgAUAAgK/xh3DwBwAgAAAA==.Yokos:BAAANQADCgMIAwAAAA==.',
Yu='Yunkali:BAAANQADCgcIDAAAAA==.',
Za='Zahneel:BAAANQAECgUICAAAAA==.Zarallia:BAAANQAECgQIBQAAAA==.Zaratul:BAACNQAFFH8LAAIKAAQKCB6EDgBeAQAKAAQKCB6EDgBeAQA1AAQKfy8AAgoACQoNJeMMAJoDAAoACQoNJeMMAJoDAAAA.Zarisong:BAAANQAECgUICQABNQAECgUICQAIAAAAAA==.',
Zh='Zhawaricus:BAAANQAECgQIBgAAAA==.Zhuri:BAAANQABCgcICwAAAA==.',
Zo='Zoburg:BAAANQAECgQIBAABNQAECgcIHgABANwiAA==.',
Zp='Zpig:BAAANQAECggICAABNQAECggICAAIAAAAAA==.',
Zu='Zugssico:BAAANQADCgYIBgAAAA==.',
Zy='Zyrian:BAAANQADCggIGwAAAA==.',
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
