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

local lookup = {'Priest-Holy','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Druid-Guardian','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Warrior-Arms','Evoker-Augmentation','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Paladin-Holy','Hunter-BeastMastery','DeathKnight-Unholy','Shaman-Elemental','DeathKnight-Blood','Shaman-Restoration','Mage-Arcane','Shaman-Enhancement','Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Mage-Frost','Hunter-Marksmanship','Rogue-Assassination','Hunter-Survival','Paladin-Protection','Evoker-Devastation','Evoker-Preservation','Rogue-Subtlety','Monk-Brewmaster','Warrior-Protection','Druid-Feral',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aassvik:BAABNQAECn8kAAIBAAcK3CIfFADRAQABAAcK3CIfFADRAQAAAA==.',
Ab='Absolute:BAACNQAFFH8UAAICAAYKFCK4AACmAQACAAYKFCK4AACmAQA1AAQKfyQAAgIACgpKJFkFAH0DAAIACgpKJFkFAH0DAAAA.',
Ac='Achelin:BAAANQADCgUIBQAAAA==.Achieved:BAACNQAFFH8RAAMDAAcKKhpTCQDqAQADAAcKKhpTCQDqAQAEAAEK1AA1GQAwAAA1AAQKfy0ABAMACgoBIyMMAGoDAAMACgoBIyMMAGoDAAQABgp/EIU7AEQBAAUAAQoAALxtACAAAAAA.Achievsome:BAABNQAECn8uAAQGAAoKPSOuAwCfAwAGAAkKeyWuAwCfAwABAAcKMxUaiQB7AQAHAAIKwBDUCABQAAAAAA==.',
Ad='Adorabull:BAAANQADCgQIBQAAAA==.',
Ae='Aesomx:BAAANQAECgEIAQABNQAECgQIDQAIAAAAAA==.Aesoxp:BAAANQAECgIIBQABNQAECgQIDQAIAAAAAA==.Aethalas:BAAANQABCgIIAgAAAA==.',
Ag='Agrajag:BAAANQADCgUIBQABNQAECgoKQAAJALEdAA==.',
Ah='Ahnruun:BAAANQAECgQIBQAAAA==.',
Ai='Aiona:BAAANQADCgQIBAAAAA==.',
Ak='Akagrats:BAAANQADCgEIAQAAAA==.',
Al='Alassar:BAAANQAECgUICwAAAA==.Alazan:BAAANQAECgQIBAAAAA==.Alcaraz:BAAANQADCggIEwAAAA==.Alessandro:BAABNQAECn8UAAIKAAgKxgkqDgBlAQAKAAgKxgkqDgBlAQAAAA==.Algas:BAAANQAECgIIAQAAAA==.Aliengrey:BAAANQAECgYICgAAAA==.Alindrin:BAAANQABCgIIAgAAAA==.Allyissa:BAAANQADCgIIAgAAAA==.Alonsusfaol:BAABNQAECn8rAAILAAoKjBMTcwBIAgALAAoKjBMTcwBIAgAAAA==.Alrsta:BAAANQADCgIIAQAAAA==.Alunarteil:BAAANQAECgEIAQAAAA==.',
Am='Amane:BAABNQAECn8wAAMMAAgKRyLSBgCnAgAMAAgKRyLSBgCnAgANAAgK0BX2NwDxAQAAAA==.American:BAAANQAECgIIAQAAAA==.Ammaydie:BAAANQADCgIIAgAAAA==.Amytenchi:BAAANQABCggIEgAAAA==.',
An='Anger:BAAANQADCggIDQAAAA==.Annya:BAABNQAECn8jAAMBAAgK4hXGUgArAgABAAgK4hXGUgArAgAGAAYKyQoSQwAbAQAAAA==.',
Ar='Archdragon:BAAANQADCgMIAwABNQAECgoKJwAEAFUkAA==.Archtrishop:BAAANQADCgEIAQAAAA==.Aristae:BAAANQABCgIIAgABNQAECggIFAALAHAJAA==.Arkanis:BAABNQAECn8zAAIOAAoKlxF9AQD7AQAOAAoKlxF9AQD7AQAAAA==.Armament:BAABNQAECn8vAAIJAAoKKhQwNABCAQAJAAoKKhQwNABCAQAAAA==.Arthus:BAAANQADCggICAAAAA==.',
As='Ashleymarion:BAAANQADCgIJAgAAAA==.',
At='Aträyu:BAAANQADCggIEAABNQAECggIFwAPAC0KAA==.Attlas:BAAANQADCgQIBAAAAA==.',
Au='Aurafiora:BAABNQAECn84AAIQAAoKtiBqDgBuAwAQAAoKtiBqDgBuAwAAAA==.Aurius:BAAANQAECgcIDgAAAA==.',
Av='Avalancha:BAABNQAECn8mAAIFAAgKqxcYFQAWAgAFAAgKqxcYFQAWAgAAAA==.Avinoch:BAAANQAECgUIEAAAAA==.',
Ax='Axon:BAAANQAECggIEAAAAA==.',
Ay='Aynhillbeads:BAAANQAECgEIAQABNQAECgUIDAAIAAAAAA==.',
Az='Azekor:BAAANQADCggIEQAAAA==.Azenroth:BAAANQAECgUICAAAAA==.Azureth:BAABNQAECn8WAAIRAAgKDhoFQwAPAgARAAgKDhoFQwAPAgAAAA==.',
Ba='Babykay:BAAANQADCgUIDQABNQAECgkJMwASAOweAA==.Bakimono:BAAANQADCgQIBAAAAA==.Banehellborn:BAAANQAECggIEAAAAA==.Barnicas:BAAANQADCgYICQABNQAECgMIAwAIAAAAAA==.Bartholomäus:BAAANQADCgUIEAAAAA==.Batmack:BAAANQABCgQIBAAAAA==.',
Bb='Bbshagoogoo:BAAANQAECgQIBgABNQAECgYIDAAIAAAAAA==.',
Be='Beezlebumon:BAABNQAECn8oAAMRAAgKghXACACnAQARAAgKghXACACnAQATAAEKmAmYzAAxAAAAAA==.Beld:BAAANQADCgcIBwAAAA==.Bellcross:BAAANQADCgUIBQAAAA==.Belloq:BAAANQAECgEJAQAAAA==.Benedis:BAAANQAECgMIAwAAAA==.Bené:BAAANQADCggICAAAAA==.Berend:BAAANQAECgUIBQAAAA==.Bewater:BAABNQAECn8oAAIQAAkKYxbagAALAgAQAAkKYxbagAALAgAAAA==.',
Bl='Blegh:BAAANQAECgIIAgABNQAFFAMIBwALAAEZAA==.Bluberry:BAAANQADCgcIGgAAAA==.Blóðugrgríma:BAAANQAECgEIAQAAAA==.',
Bo='Bobabear:BAAANQAECgEIAQAAAA==.Bonersimpsun:BAABNQAECn8fAAIRAAgKJiAhBgDQAQARAAgKJiAhBgDQAQAAAA==.Boomchicken:BAAANQADCgMIAwAAAA==.Boomclap:BAABNQAECn8vAAMUAAoKOhsmKgC7AgAUAAoKOhsmKgC7AgASAAIKkAf7kQA3AAAAAA==.',
Bp='Bpbreezy:BAACNQAFFH8PAAIBAAMKkhuhHQD1AAABAAMKkhuhHQD1AAA1AAQKfywAAwEACgrFHmQdAPwCAAEACgrFHmQdAPwCAAYAAwrdE5tQAM8AAAAA.',
Br='Bracknor:BAABNQAECn8dAAIQAAgKKhF8fAAVAgAQAAgKKhF8fAAVAgAAAA==.Brakdread:BAAANQADCgEIAQAAAA==.Brandonb:BAABNQAECn9CAAIVAAoKIyAeAwDOAgAVAAoKIyAeAwDOAgAAAA==.Brandonresha:BAAANQAECgEIAQAAAA==.Brandonw:BAAANQAECgUIDQAAAA==.Bredock:BAAANQAECgUICQABNQAFFAYIFQAQAFIaAA==.Brittlehorn:BAAANQADCgYIBgAAAA==.Brotem:BAABNQAECn8eAAIWAAoKvRcGDACvAgAWAAoKvRcGDACvAgAAAA==.Brucejenner:BAAANQAECggICAAAAA==.Brutalisto:BAAANQAECgYIDQAAAA==.Bryanthesly:BAAANQADCggIFAAAAA==.',
By='Bysokar:BAABNQAECn8fAAIXAAkKdxo4FQCqAgAXAAkKdxo4FQCqAgAAAA==.',
Ca='Cainfortea:BAAANQAECgIIBAAAAA==.Cakel:BAAANQADCgcIBwAAAA==.Calipal:BAAANQAECggICwAAAA==.Calipriest:BAAANQADCgQIAgAAAA==.Calisha:BAAANQADCgQIBAAAAA==.Catalinaholy:BAAANQAECggIDwABNQAFFAYKCgAUAIkUAA==.Catalinasham:BAACNQAFFH8KAAIUAAYKiRRBDgBpAQAUAAYKiRRBDgBpAQA1AAQKfxwAAhQACQrRIv8XABMDABQACQrRIv8XABMDAAE1AAUUBgoKABQAiRQA.Cataster:BAAANQADCgcIAwAAAA==.Cazadore:BAAANQADCggIDwAAAA==.',
Ce='Celardron:BAAANQAECgMIAwAAAA==.Celebrimbjor:BAAANQAECgEIAQAAAA==.Cerberusbone:BAAANQAECgUIEAAAAA==.',
Ch='Challengerz:BAAANQAECgUIDwAAAA==.Charliehorse:BAAANQADCgQIBAAAAA==.Chopper:BAAANQAECgYIEAAAAA==.',
Ci='Cinderlily:BAAANQAECgUIDgAAAA==.',
Cl='Clayprincess:BAAANQADCgYICAABNQAECggIDAAIAAAAAA==.',
Co='Conflagrate:BAACNQAFFH8PAAMYAAQKZBl1AwCNAAAZAAQKmxWsGQAoAQAYAAIKZwx1AwCNAAA1AAQKfyAABBkACgqjH+8ZAB8DABkACgqjH+8ZAB8DABoAAQoAAKknAE0AABgAAQprGidrAEoAAAAA.Connery:BAAANQADCgcIHAAAAA==.Cornpopp:BAAANQADCgYIDwAAAA==.Coryuchiha:BAAANQADCgQIBQAAAA==.',
Cp='Cptcrushingb:BAAANQADCggIEAAAAA==.',
Cr='Crax:BAAANQADCgMIBAAAAA==.Crithappens:BAAANQAECgUIBAAAAA==.Criturrpants:BAAANQAECggICwAAAA==.Crouch:BAAANQAECgIIAgAAAA==.',
Cy='Cynnå:BAABNQAECn8dAAIVAAkKlRhUWgDLAgAVAAkKlRhUWgDLAgAAAA==.Cynthea:BAAANQADCgMJAwAAAA==.Cyp:BAABNQAECn8wAAIJAAkKGRgWaABYAgAJAAkKGRgWaABYAgAAAA==.',
['Cü']='Cüpcake:BAAANQAECggIEAAAAA==.',
Da='Dababycar:BAAANQAECgcIEgAAAA==.Dabbyduck:BAABNQAECn8iAAMZAAkK7BmONAC4AgAZAAkK7BmONAC4AgAYAAcKLg4fGQCjAQAAAA==.Dambalah:BAAANQAECgEIAQAAAA==.Damsure:BAAANQAECgUIBgAAAA==.Danifru:BAAANQAECgYIBwAAAA==.Darren:BAAANQABCggIEgAAAA==.',
De='Deadincide:BAEBNQAECn8mAAIRAAkKsRMbQgATAgARAAkKsRMbQgATAgAAAA==.Deadstasheo:BAACNQAFFH8NAAIRAAQKKiNzAQAtAQARAAQKKiNzAQAtAQA1AAQKfyYAAhEACgoUIpYYAPoCABEACgoUIpYYAPoCAAAA.Deathblight:BAAANQADCgYIBAAAAA==.Decree:BAABNQAECn8hAAILAAgKLxZKJwCJAQALAAgKLxZKJwCJAQAAAA==.Deezmonz:BAAANQAECgUICgABNQAECgoKQAAJALEdAA==.Delik:BAABNQAECn8mAAIbAAgKkhaNCQA6AgAbAAgKkhaNCQA6AgAAAA==.Deluded:BAAANQAECggICQAAAA==.Demonarch:BAAANQADCgYICgAAAA==.Demonlordmeh:BAAANQADCgUICQAAAA==.Demïse:BAAANQADCgcICQAAAA==.Dendrite:BAAANQAECgMIAwAAAA==.Deneol:BAABNQAECn8kAAMGAAoKoBcfEQDoAgAGAAoKoBcfEQDoAgAHAAEK3BG+JwA3AAAAAA==.Destrogen:BAACNQAFFH8FAAIaAAMKJApvAADwAAAaAAMKJApvAADwAAA1AAQKfyAABBoACQp8F9ABAIwBABoACAqLGdABAIwBABkABAqNCyv2AN8AABgAAgqkDQFcAG4AAAAA.Desìre:BAABNQAECn8lAAIHAAgK+R40AwDJAgAHAAgK+R40AwDJAgAAAA==.Deäthgär:BAAANQADCgMIAwABNQAECggIFwAPAC0KAA==.',
Di='Diabolic:BAAANQADCggICAAAAA==.Dirty:BAAANQADCggIGQAAAA==.Discotheque:BAAANQADCgMIAwAAAA==.',
Dk='Dksura:BAABNQAECn8rAAIRAAoK4R2+AwAQAgARAAoK4R2+AwAQAgAAAA==.',
Do='Doomknight:BAAANQADCgcIFAAAAA==.Doomshield:BAAANQAECgQIBQAAAA==.Doomshroud:BAAANQABCgUIBQABNQAECgYIDgAIAAAAAA==.Doomwing:BAAANQADCgYIBgAAAA==.',
Dr='Dracodeez:BAAANQAECggIDwAAAA==.Driretlan:BAAANQADCgYIBwAAAA==.Druss:BAABNQAECn8kAAMRAAkKvR+CDgBEAwARAAkKvR+CDgBEAwATAAQKZBcXjwDHAAAAAA==.',
Du='Dumbledog:BAAANQABCgQIBAAAAA==.Durunk:BAAANQAECgUIDgAAAA==.',
Dz='Dzimps:BAAANQAECgMIAwAAAA==.',
['Dë']='Dëlètêd:BAAANQAECggIEQAAAA==.',
['Dì']='Dìesèl:BAAANQAECggICAABNQAECggIEQAIAAAAAA==.',
Ei='Eileen:BAAANQABCgIIBQAAAA==.',
El='Elemeesel:BAAANQADCggJCAAAAA==.Eleroeda:BAAANQADCgcIBwAAAA==.',
En='Endeavor:BAAANQAECgQIBwAAAA==.',
Eq='Equâs:BAAANQADCgcIDAABNQAECgMICQAIAAAAAA==.',
Er='Eradion:BAAANQADCggIDQAAAA==.Eredarlord:BAAANQAECggIDAAAAA==.Erelm:BAAANQAECgcIEQAAAA==.Erisson:BAABNQAECn8fAAIQAAgK7xIwSAAjAQAQAAgK7xIwSAAjAQAAAA==.Errorèdivina:BAAANQAECgQIAgABNQAECggKKAAcACALAA==.',
Es='Eszran:BAAANQAECgcICwAAAA==.',
Eu='Euthanized:BAAANQAECgIIBwAAAA==.',
Fe='Felviiv:BAAANQAECgYICAAAAA==.Fennar:BAAANQAECgIIBQAAAA==.Ferosha:BAABNQAECn81AAITAAoKUR9aEgAaAwATAAoKUR9aEgAaAwABNQAECgMIAwAIAAAAAA==.Fexxyr:BAAANQAECgQIBAABNQAFFAUIEwAGANIQAA==.',
Fi='Fiadh:BAAANQADCgQIBAAAAA==.Fiendishtwin:BAAANQADCgMIAwAAAA==.Firm:BAAANQADCgUICgAAAA==.Firstfear:BAAANQADCgYICwAAAA==.Fisch:BAAANQAECggIDwAAAA==.Fischglizzy:BAAANQADCgYIBgAAAA==.',
Fl='Flemtok:BAAANQAECggIAQAAAA==.Flidd:BAAANQAECgcICgAAAA==.Flipingtiska:BAAANQAECgEIAQAAAA==.Floisa:BAAANQADCgQIBAAAAA==.Flynae:BAAANQAECggIEgAAAA==.',
Fo='Fontingaul:BAAANQAECgUICQAAAA==.',
Fr='Fragtastic:BAABNQAECn83AAMQAAoK5hupJACGAQAcAAcKcRYBLwDUAQAQAAYKyx2pJACGAQAAAA==.Frearyne:BAABNQAECn8nAAIEAAoKVSRUAgCpAwAEAAoKVSRUAgCpAwAAAA==.Frinu:BAAANQAECgQIBQABNQABCgIIAgAIAAAAAA==.Frogs:BAAANQADCggIKwAAAA==.Frostyshadow:BAABNQAECn8rAAIVAAkKESHGHABkAwAVAAkKESHGHABkAwAAAA==.Frozatresh:BAAANQAECgEIAQAAAA==.',
Fs='Fstingnemo:BAABNQAECn8hAAIXAAkKzBUdIwAOAgAXAAkKzBUdIwAOAgAAAA==.',
Fy='Fyxxer:BAAANQADCgIIAgABNQAFFAUIEwAGANIQAA==.Fyxxie:BAACNQAFFH8TAAIGAAUK0hDtCAB7AQAGAAUK0hDtCAB7AQA1AAQKfy4AAwYACgqpGysJAGIBAAYACgqpGysJAGIBAAcAAQrYHm0hAFgAAAAA.',
Ga='Gaucho:BAAANQABCgIIAgAAAA==.',
Ge='Genvissa:BAABNQAECn8WAAIZAAkKRxEObAAZAgAZAAkKRxEObAAZAgAAAA==.',
Gi='Gialiana:BAABNQAECn8eAAIcAAkKQBQaLADqAQAcAAkKQBQaLADqAQAAAA==.Githryn:BAAANQABCgcIBwAAAA==.',
Gl='Glorpschlorp:BAAANQAECgcIBwABNQAFFAYIFAACABQiAA==.',
Go='Goobby:BAAANQADCgcIDAAAAA==.',
Gr='Grassfed:BAAANQAECgcIEwAAAA==.Greenymeany:BAABNQAECn8dAAIOAAYKvx11DAD0AQAOAAYKvx11DAD0AQAAAA==.Grizzlethorn:BAAANQAECgEIAQABNQAECgcIEQAIAAAAAA==.Grully:BAABNQAECn8iAAIUAAoKRwwfZwDXAQAUAAoKRwwfZwDXAQAAAA==.',
Gu='Gurt:BAAANQAECggIDAAAAA==.Guzzug:BAABNQAECn9AAAIJAAoKsR10BQB+AgAJAAoKsR10BQB+AgAAAA==.',
Gw='Gwumpy:BAAANQAECgEIAgAAAA==.',
Ha='Haggard:BAABNQAECn8iAAICAAgKRxp8GgCFAgACAAgKRxp8GgCFAgAAAA==.Hailsbelle:BAAANQAECggIEAAAAA==.Harleymama:BAAANQABCgIIAgAAAA==.Hashtag:BAAANQADCgUIEQAAAA==.',
Hb='Hbic:BAAANQAECgUIBgAAAA==.',
He='Healyboar:BAAANQADCgUIBQAAAA==.Heartstabber:BAABNQAECn8uAAIdAAgKRRaaLQAvAgAdAAgKRRaaLQAvAgAAAA==.Helado:BAAANQAECgQIDQAAAA==.Hellbane:BAAANQADCgYIBgAAAA==.',
Hi='Highwayman:BAAANQAECgUICgABNQAECgoKQgAQAHIjAA==.',
Ho='Holyling:BAAANQADCgYIBgAAAA==.Holys:BAAANQAECgcIBwAAAA==.Hondurasman:BAAANQADCgEIAQAAAA==.Honkhonk:BAABNQAECn8UAAILAAYKzxEy2gBnAQALAAYKzxEy2gBnAQAAAA==.',
Hr='Hraktar:BAAANQADCgEIAQAAAA==.',
Ic='Icwiener:BAAANQAECgUIDAAAAA==.',
Ie='Ieva:BAAANQADCgYIEQAAAA==.Ievil:BAABNQAECn8fAAMRAAgK8wstJQDSAAARAAgK8wstJQDSAAATAAEKAABK3QAhAAAAAA==.',
Ik='Ikasha:BAAANQAECgYIBgAAAA==.',
Il='Ilyss:BAAANQAECgYIBgABNQAECgoKQAANAC0iAA==.',
Im='Imjustpika:BAACNQAFFH8SAAIeAAYKGhFXAAAdAgAeAAYKGhFXAAAdAgA1AAQKfyMAAh4ACgr3GfwEAH8CAB4ACgr3GfwEAH8CAAAA.',
In='Inawee:BAABNQAECn9CAAIEAAoK2hsSBwDWAQAEAAoK2hsSBwDWAQAAAA==.Inferniö:BAACNQAFFH8UAAIVAAYK4xzuCAA5AgAVAAYK4xzuCAA5AgA1AAQKfzcAAhUACgr5Ix0QAJIDABUACgr5Ix0QAJIDAAAA.Inkurushio:BAAANQAECgIIBAAAAA==.Intothefray:BAAANQADCgUIBQAAAA==.',
Io='Iolanie:BAAANQADCggICAAAAA==.',
Is='Ismat:BAABNQAECn9CAAIUAAoKGQ2EFACwAQAUAAoKGQ2EFACwAQAAAA==.',
Ja='Jaqu:BAAANQAECgEIAQAAAA==.Jarshh:BAAANQAECggIDwAAAA==.',
Jo='Jonald:BAAANQAECgUIBQAAAA==.Jorrick:BAAANQAECgEIAgAAAA==.',
Ju='Judge:BAABNQAECn8fAAQfAAkKbxyeAgAWAgAfAAgKDh+eAgAWAgAPAAMKSwSR/QCBAAALAAMKRw25dgFmAAABNQAECgMIAwAIAAAAAA==.Juura:BAABNQAECn8eAAIYAAkKJBIzAQCbAQAYAAkKJBIzAQCbAQAAAA==.',
Ka='Kaedra:BAAANQADCggICAAAAA==.Kalukaynas:BAABNQAECn8YAAIPAAoKMBktKwA2AQAPAAoKMBktKwA2AQAAAA==.Karrog:BAAANQABCgQIBAAAAA==.Karsen:BAAANQAECggIEAAAAA==.Kassian:BAAANQABCgIIAgAAAA==.Kaveros:BAAANQAECgYIEgAAAA==.',
Ke='Kelaan:BAABNQAECn8dAAMfAAgKbSLyAwDVAQAfAAgKbSLyAwDVAQALAAEKAAAuoQE2AAAAAA==.Kelimao:BAAANQAECgcIDAAAAA==.Kendrà:BAAANQADCgIIAgAAAA==.Kevron:BAAANQAECgQIBgAAAA==.',
Ki='Kiimagi:BAAANQADCgEIAQAAAA==.Killingame:BAAANQABCgEIAQAAAA==.Kiritos:BAABNQAECn8ZAAIEAAkKWiDEDwDbAgAEAAkKWiDEDwDbAgAAAA==.Kiserys:BAABNQAECn8WAAMgAAcKJhAeGgCnAQAgAAcKJhAeGgCnAQAhAAQK/xHWNQDlAAAAAA==.',
Ko='Koharu:BAAANQABCgcICgAAAA==.Kollia:BAAANQADCgEIAgAAAA==.Korena:BAAANQADCgUIBwAAAA==.Kostard:BAAANQAECgEIAQAAAA==.',
Kr='Krysto:BAABNQAECn8jAAIQAAgKZgoekADpAQAQAAgKZgoekADpAQAAAA==.',
Ku='Kukulkan:BAAANQADCgQIBAAAAA==.Kurlabji:BAAANQADCgUIBQAAAA==.',
Kw='Kwatli:BAAANQADCgYIBgAAAA==.',
La='Lanaela:BAAANQABCgIIBwAAAA==.Laquisha:BAAANQAECgEIAQAAAA==.Latchless:BAAANQAECgIIAgAAAA==.',
Le='Lenin:BAAANQAECgQIBQAAAA==.',
Li='Lightmasta:BAAANQADCgYIBgAAAA==.Liily:BAAANQADCggIDAAAAA==.Likdiso:BAAANQADCgcIBwAAAA==.Lilatharia:BAAANQABCgIIAgAAAA==.Lilydari:BAAANQADCgEIAQAAAA==.Lizzmo:BAAANQABCgQIBAAAAA==.',
Lo='Lookforlight:BAABNQAECn9NAAMLAAoKVyBYHwBGAwALAAoKVyBYHwBGAwAfAAEK+iOSXgBgAAAAAA==.Lorenth:BAAANQAECggIDwAAAA==.',
Lu='Lucid:BAAANQAECgUICwAAAA==.Luckyjade:BAAANQAECgMIBgAAAA==.',
Lv='Lvcky:BAAANQADCgIIAgAAAA==.',
['Lì']='Lìte:BAABNQAECn8iAAICAAcKkQ7iEQAjAQACAAcKkQ7iEQAjAQAAAA==.',
Ma='Mabi:BAAANQADCgUIBQAAAA==.Macarthur:BAABNQAECn8uAAMiAAgK8Al7HwDUAQAiAAgK8Al7HwDUAQAdAAEKhgeVUAA1AAAAAA==.Madcowburger:BAAANQADCgYICwAAAA==.Mageyoulookk:BAAANQADCgIIAgAAAA==.Maizuko:BAAANQADCgUIBQABNQAECgkJHAATAO0bAA==.Malagu:BAAANQAECgIIBAABNQAECgkJKwAVABEhAA==.Malidros:BAAANQAECgQIBAABNQAECgUIBQAIAAAAAA==.Malign:BAABNQAECn8aAAMdAAoKPiOtAwCcAwAdAAkKiSOtAwCcAwAiAAMKUSGYFQAuAQABNQAFFAYIFAACABQiAA==.Manhatten:BAAANQAECgQIBQAAAA==.Manogawd:BAAANQADCgQIBAAAAA==.Marhault:BAABNQAECn9CAAMQAAoKciOoAABDAwAQAAoKYCOoAABDAwAeAAUKbR9MCwBFAQAAAA==.Maria:BAAANQAECgEIAQAAAA==.Marriage:BAAANQADCgcIBwAAAA==.Masitaka:BAABNQAECn8cAAITAAkK7RvZJACTAgATAAkK7RvZJACTAgAAAA==.Maxicat:BAAANQAECgMIBAAAAA==.Maximus:BAABNQAECn8aAAILAAYKbxGb2ABqAQALAAYKbxGb2ABqAQAAAA==.Mazah:BAABNQAECn9CAAMSAAoKHRaVBQAaAgASAAoKHRaVBQAaAgAUAAIKlQInDAFQAAAAAA==.Mazlo:BAACNQAFFH8FAAIbAAMKnxBJCACXAAAbAAMKnxBJCACXAAA1AAQKfzYAAxsACgo9HRAEAPUCABsACgo9HRAEAPUCABUAAgrrAP3DATgAAAAA.',
Me='Meibao:BAAANQAECgMIAwAAAA==.Meleebrain:BAAANQABCgEJAQABNQAECgoKQAAJALEdAA==.Mellethir:BAABNQAECn8xAAMVAAkKTgpv5gC9AQAVAAkKTgpv5gC9AQAbAAIK1glVEQB3AAAAAA==.Messalina:BAAANQAECgUIBQAAAA==.Mex:BAAANQADCggIDAAAAA==.',
Mi='Millîe:BAAANQAECgIIBAAAAA==.Minipimp:BAAANQADCgYIGAAAAA==.Mirajane:BAAANQADCgIIAgAAAA==.Missoxx:BAAANQAECgQIBQAAAA==.Mistbringer:BAAANQAECgYIEAAAAA==.',
Mo='Moarhots:BAAANQADCgIIAgAAAA==.Mofoasso:BAABNQAECn8kAAIQAAgKxx89BgBnAgAQAAgKxx89BgBnAgAAAA==.Moglayn:BAABNQAECn9AAAITAAoK/SPXAAAeAwATAAoK/SPXAAAeAwAAAA==.Monkazz:BAAANQADCgQIBAAAAA==.Monkorith:BAECNQAFFH8JAAIjAAQKWQ1uBgD4AAAjAAQKWQ1uBgD4AAA1AAQKfxsAAiMACQpOGnENACQCACMACQpOGnENACQCAAE1AAUUBggQABMAhA8A.Monorìth:BAEBNQAFFH8QAAITAAYKhA9uDgBtAQATAAYKhA9uDgBtAQAAAA==.Morninstar:BAAANQADCgMIAwAAAA==.Mortalkon:BAAANQADCgYJBgAAAA==.Mortis:BAAANQADCgIIAgAAAA==.',
Mu='Mullett:BAAANQADCgMIAwABNQAECggILgAiAPAJAA==.',
My='Myspace:BAAANQADCgcICQAAAA==.Mystogaan:BAAANQADCgQJBQAAAA==.',
['Mã']='Mãdmåx:BAAANQABCggIEQABNQABCggIFgAIAAAAAA==.',
['Mø']='Mørbid:BAAANQADCggICAAAAA==.',
Na='Nakiki:BAAANQAECgQICQAAAA==.Nastyiam:BAABNQAECn8oAAIWAAoKoxP8DQCNAgAWAAoKoxP8DQCNAgAAAA==.',
Ne='Nerfornothin:BAABNQAECn8XAAIQAAgK5AV80gBbAQAQAAgK5AV80gBbAQAAAA==.Nethflap:BAABNQAECn8oAAIhAAkK6RA8GwAUAgAhAAkK6RA8GwAUAgAAAA==.Nezhi:BAAANQADCgIIAgAAAA==.',
Ni='Nialin:BAAANQADCggIIgAAAA==.Nifru:BAAANQADCgMIAwAAAA==.Niik:BAABNQAECn8nAAIUAAoK/xhKMQCcAgAUAAoK/xhKMQCcAgAAAA==.',
No='Norgahl:BAAANQADCgMIBAAAAA==.Nosferato:BAAANQADCgEIAQAAAA==.',
Nu='Nutmilker:BAABNQAECn8sAAIWAAoK2SO/AQCcAwAWAAoK2SO/AQCcAwAAAA==.',
Ny='Nyxnight:BAAANQADCgEIAQAAAA==.',
Ob='Obi:BAAANQAECgIIAgAAAA==.',
Om='Omacron:BAAANQADCgEIAQAAAA==.',
Or='Oriion:BAAANQADCgMIBQAAAA==.Orthae:BAAANQADCggIGgABNQAECgYICgAIAAAAAA==.',
Os='Osanyin:BAAANQADCgQIBAABNQAECgUIBQAIAAAAAA==.',
Ou='Outstanding:BAAANQADCgYIDAABNQAECgcIJAABANwiAA==.',
Oz='Ozzyzomborne:BAAANQADCggIDgAAAA==.',
Pa='Pandoosevelt:BAAANQADCgMIAwAAAA==.',
Pe='Pepis:BAAANQAECgQICQAAAA==.',
Ph='Phemera:BAAANQADCgMIAwAAAA==.Philidan:BAAANQAECgUICQAAAA==.Phyrra:BAAANQADCgEIAQAAAA==.',
Pi='Picklerickz:BAAANQAECgIIAgAAAA==.Pikagosa:BAAANQABCgEIAQABNQAFFAYIEgAeABoRAA==.Pilgor:BAAANQAECggIEgAAAA==.Pirlivewire:BAAANQABCgQIBAABNQABCgQIBAAIAAAAAA==.',
Pl='Plagué:BAAANQAECgEIAQAAAA==.',
Po='Pohaku:BAAANQAECgQICQAAAA==.Polkovnik:BAABNQAECn8fAAIJAAkKVRvFZQBeAgAJAAkKVRvFZQBeAgAAAA==.Powderjinx:BAAANQADCgQIBQAAAA==.',
Pr='Pravaat:BAAANQAECgYIDgAAAA==.Prayvus:BAAANQADCgIIAgAAAA==.Preroll:BAAANQADCgEIAQAAAA==.Prisonsoul:BAAANQADCgcIDQAAAA==.',
Py='Pylon:BAAANQADCgUICAAAAA==.',
Qu='Qubit:BAEBNQAECn8XAAIVAAcK7gQjZQDzAAAVAAcK7gQjZQDzAAABNQAECgkJJgARALETAA==.Quiniustius:BAAANQAECgQIBQAAAA==.',
Ra='Ragingpwner:BAAANQADCgUIBQAAAA==.Rallyn:BAAANQADCggICAAAAA==.Rast:BAAANQAECgQICgAAAA==.Rastabout:BAAANQADCggICwABNQAECgkJMwASAOweAA==.Ravel:BAAANQAECgcIDwAAAA==.',
Re='Reahla:BAAANQADCgcIBwAAAA==.Reclaim:BAABNQAECn8zAAMSAAkK7B6AKADfAgASAAkK7B6AKADfAgAWAAIKtgItHABfAAAAAA==.Reios:BAABNQAECn8lAAIZAAgKrRtLQgCLAgAZAAgKrRtLQgCLAgAAAA==.',
Rh='Rhaego:BAAANQAECgUIBQAAAA==.Rhaz:BAABNQAECn8kAAMPAAcKBQ38LwAjAQAPAAcKBQ38LwAjAQALAAEKAADpvAEqAAAAAA==.Rheeannon:BAAANQABCgQIBgAAAA==.Rhikre:BAAANQADCgUIBQAAAA==.Rhoup:BAAANQADCgcIBgABNQAECggIFwAeACcaAA==.',
Ri='Rickyspanish:BAABNQAECn8xAAICAAkKwCCFDQANAwACAAkKwCCFDQANAwAAAA==.Rifter:BAAANQAECgQIBQAAAA==.Rikkibobbi:BAAANQADCgMIAwABNQADCgYIBgAIAAAAAA==.Ripnmaim:BAEANQADCgYIBgABNQAECgkJJgARALETAA==.Rivensong:BAAANQAECgYICwAAAA==.',
Ro='Romeric:BAAANQADCggIDgAAAA==.Rontastico:BAAANQADCgIIAgAAAA==.Ronuswanson:BAAANQADCgcIFgAAAA==.Roupert:BAABNQAECn8XAAIeAAgKJxq7BQBXAgAeAAgKJxq7BQBXAgAAAA==.',
Ru='Rubyouraw:BAAANQAECgcICgAAAA==.Ruffneck:BAABNQAECn8nAAIQAAgKWBRHIACWAQAQAAgKWBRHIACWAQAAAA==.Russk:BAAANQAECgYIBwAAAA==.',
['Rû']='Rûsko:BAAANQADCgYICwAAAA==.',
Sa='Saelaan:BAABNQAECn8bAAIjAAcKVx7/AwBYAQAjAAcKVx7/AwBYAQABNQAECggIHQAfAG0iAA==.Sailfu:BAACNQAFFH8VAAIXAAYKgSB/AQB2AQAXAAYKgSB/AQB2AQA1AAQKfy0AAhcACgroJMgFAHQDABcACgroJMgFAHQDAAE1AAUUBggUAAIAFCIA.Saiyurie:BAAANQABCgIIAgAAAA==.Sakrine:BAAANQAECgEIAQAAAA==.Salami:BAAANQADCgcIDgAAAA==.Samo:BAABNQAECn8iAAIGAAcKvB4CBgCaAQAGAAcKvB4CBgCaAQAAAA==.Sandarr:BAABNQAECn8fAAIfAAcK+Ri3IgDMAQAfAAcK+Ri3IgDMAQAAAA==.Sanguinne:BAAANQAECgUIDwAAAA==.Santhus:BAAANQAECgUIDgABNQAECggICwAIAAAAAA==.Saretae:BAAANQADCggIHQABNQAFFAYIFAAVAOMcAA==.Sargemarge:BAABNQAECn8dAAIUAAkKICMxDQBXAwAUAAkKICMxDQBXAwAAAA==.Sarume:BAAANQAECgYIAwAAAA==.',
Sc='Sci:BAABNQAECn8tAAIPAAgKGyUPEABLAwAPAAgKGyUPEABLAwAAAA==.',
Se='Seafoame:BAAANQADCggICAAAAA==.Selener:BAAANQAECgYICwAAAA==.Serrata:BAAANQAECgYIDAAAAA==.Seymorweiner:BAAANQADCgQIBQAAAA==.',
Sh='Shaanks:BAAANQADCggIDAAAAA==.Shadowplay:BAEANQADCggIEwABNQAECgkJJgARALETAA==.Shamski:BAAANQAECgEIAQABNQAECgUICQAIAAAAAA==.Shamydavisjr:BAAANQABCggIFgAAAA==.Shankles:BAAANQADCgIJAgAAAA==.Shareen:BAAANQAECgMIBAAAAA==.Shathice:BAAANQADCgIIAgABNQAECgoKGAAPADAZAA==.Shiftyfrogs:BAAANQADCgIIAgAAAA==.Shkar:BAAANQAECgEIAQAAAA==.',
Si='Sidelvar:BAAANQABCggIFAAAAA==.Silandros:BAAANQAECgIIAgAAAA==.Silther:BAAANQAECggIDwAAAA==.',
Sk='Skarath:BAABNQAECn8aAAQOAAUK+wcqJACSAAAkAAQKzwooMQCtAAAOAAUKoAQqJACSAAAJAAMKTwPHTQE5AAAAAA==.',
Sl='Slavka:BAAANQADCgQIBgAAAA==.',
Sm='Smaalls:BAAANQAECgEIAQAAAA==.Smote:BAAANQADCggICwAAAA==.',
Sn='Snâppy:BAABNQAECn8iAAIEAAcKdA0IGAACAQAEAAcKdA0IGAACAQAAAA==.',
So='Societte:BAAANQAECgEIAQAAAA==.Soloron:BAABNQAECn8lAAIUAAgKPBlxGACVAQAUAAgKPBlxGACVAQAAAA==.Sorrowsöng:BAAANQAECggIDwAAAA==.Soulbrother:BAAANQAECggICAABNQAECggICAAIAAAAAA==.Southvik:BAAANQAECgQIBAABNQAECgcIJAABANwiAA==.',
Sp='Spamlock:BAAANQAECgMIAwABNQAFFAMIDwABAJIbAA==.Sparrhawk:BAAANQAECgMIBQAAAA==.Spiced:BAABNQAECn8fAAIDAAkKySEQDgBaAwADAAkKySEQDgBaAwAAAA==.Spiceweasel:BAAANQAECgMIAwAAAA==.Spirithaeler:BAAANQABCgIIAgAAAA==.Spood:BAABNQAECn8oAAMHAAoKvw/2DgA9AQAHAAUKkRP2DgA9AQAGAAoKCQwsDAA6AQAAAA==.',
St='Stabulóus:BAAANQADCggIAQAAAA==.Stabussy:BAAANQAECgMIAgABNQAECgYIDAAIAAAAAA==.Starskream:BAAANQADCgQIBAAAAA==.Steelarrow:BAAANQADCgUIBQAAAA==.Steliokontos:BAAANQABCgIIAgAAAA==.Stickes:BAAANQAECgQIBAAAAA==.Stingella:BAAANQADCgUIBwAAAA==.Stormclaw:BAAANQADCggIDgABNQAECgkJFgAZAEcRAA==.Stormfall:BAAANQADCgYIEQAAAA==.Sttriker:BAABNQAECn8WAAINAAgKnAOUZwDbAAANAAgKnAOUZwDbAAAAAA==.Styx:BAAANQABCgQIBAABNQADCgIIAgAIAAAAAA==.',
Sy='Synsairis:BAAANQAECggIDwAAAA==.',
Ta='Talenelat:BAAANQAECgIIAQAAAA==.Talonknight:BAABNQAECn8iAAMKAAcKOQx9BADuAAAKAAcK3At9BADuAAAgAAUK1QauKQDdAAAAAA==.Tau:BAAANQAECggIDwAAAA==.Taurrows:BAAANQABCggIIQAAAA==.Tavaran:BAAANQABCgUIBgAAAA==.Tavinz:BAAANQAECgIIBAAAAA==.',
Te='Tempedsoul:BAAANQABCgcIDQAAAA==.',
Th='Thaendofyou:BAAANQAECggICwAAAA==.Thalonis:BAAANQABCgYIBgAAAA==.Theladyheir:BAAANQAECgEJAQAAAA==.Thelas:BAAANQAECgMICQAAAA==.Thellan:BAAANQADCgYIBgAAAA==.Themonk:BAAANQADCggICgABNQAECggIKgATAIMWAA==.Therise:BAABNQAECn8gAAMMAAgKpQ7hFABeAQAMAAcKsg/hFABeAQANAAEKYwnvTgA5AAABNQAECgoKQgASAB0WAA==.Thetank:BAABNQAECn8qAAITAAgKgxZYQgDzAQATAAgKgxZYQgDzAQAAAA==.Thoroughbred:BAAANQADCgYICwAAAA==.Throwdini:BAABNQAECn8oAAIQAAkKABLuGgCtAQAQAAkKABLuGgCtAQAAAA==.Thunder:BAAANQABCgIIAgABNQABCgQIBAAIAAAAAA==.Thunderegg:BAAANQAECgUICgABNQAECgoKQgASAB0WAA==.Thundermaker:BAAANQAECgUICAABNQAECgkJJAARAL0fAA==.',
Ti='Timotthy:BAABNQAECn8fAAQFAAgKEh9DEwAvAgAFAAYKPiBDEwAvAgAlAAcKGBnQCAAZAQADAAEKAACBygAXAAAAAA==.Tixxle:BAAANQADCggIGAAAAA==.',
Tm='Tmate:BAAANQADCgQIBAAAAA==.',
To='Totemaka:BAAANQADCgUIBQAAAA==.Touchmé:BAAANQADCgQIBAAAAA==.Tousle:BAAANQAECgcICQABNQAFFAQIDwAYAGQZAA==.',
Tr='Treateak:BAAANQAECgQIBgAAAA==.Treb:BAAANQADCggICAAAAA==.Trotsky:BAABNQAECn8VAAISAAkKvBsBLwDAAgASAAkKvBsBLwDAAgAAAA==.Trögdor:BAAANQADCgUIBQAAAA==.',
Tu='Tulanis:BAABNQAECn9BAAIcAAoKLhnXAgAOAgAcAAoKLhnXAgAOAgAAAA==.Turbotax:BAAANQADCgEIAQAAAA==.',
Tw='Twerker:BAAANQADCgYIBgAAAA==.',
Ty='Tyfa:BAABNQAECn8YAAIbAAcKdBnWCQAxAgAbAAcKdBnWCQAxAgAAAA==.Tyriem:BAABNQAECn8fAAIQAAoKVBRXQACqAgAQAAoKVBRXQACqAgAAAA==.Tyssanton:BAABNQAECn8eAAMgAAgKRwONIwAnAQAgAAgKRwONIwAnAQAhAAcK4gM7MQARAQAAAA==.',
Tz='Tziganin:BAAANQAECggIDQAAAA==.',
Ug='Uggork:BAAANQADCgQIBwABNQAECgoKGAAPADAZAA==.',
Un='Unholybussy:BAAANQAECggIDgAAAA==.',
Ut='Utaadh:BAABNQAECn8pAAINAAkKSRJwNwD1AQANAAkKSRJwNwD1AQAAAA==.',
Va='Vael:BAAANQAECgUIDgABNQAECgoKQAANAC0iAA==.Vaelhorn:BAAANQAECgMIAwABNQAECgcIEQAIAAAAAA==.Vallerin:BAABNQAECn8lAAIWAAkKfhMtAwDxAQAWAAkKfhMtAwDxAQAAAA==.',
Ve='Velaar:BAAANQAECgIIAgABNQAECgoKQAANAC0iAA==.Velazar:BAAANQADCgMIAwAAAA==.',
Vi='Vicente:BAAANQAECgMIAwAAAA==.Vicenti:BAAANQADCgYIEQAAAA==.Victory:BAAANQADCgYIBgAAAA==.Vikthyr:BAAANQADCgUIBgABNQAECgcIJAABANwiAA==.Vikzul:BAAANQADCgEIAQAAAA==.Virginslyer:BAAANQAECgMIAwAAAA==.',
Vo='Vodnar:BAACNQAFFH8VAAIQAAYKUhoQBQAGAgAQAAYKUhoQBQAGAgA1AAQKfysABBAACgqdHYEwANsCABAACgqdHYEwANsCABwAAQpBGIqBAEEAAB4AAQoAAGwTADUAAAAA.',
Vu='Vulnixia:BAABNQAECn8kAAITAAgKYRsPLQBiAgATAAgKYRsPLQBiAgAAAA==.',
Wa='Wagwan:BAAANQAECgQIDQAAAA==.Walls:BAABNQAECn8UAAILAAgKcAmj3ABiAQALAAgKcAmj3ABiAQAAAA==.Wardrik:BAAANQADCgUJBQAAAA==.Waste:BAAANQAECggIDwAAAA==.Wawel:BAABNQAECn8kAAQhAAoK5h7XIQC+AQAhAAYKkCDXIQC+AQAgAAgKXRxaAwCAAQAKAAQKAxk+FADrAAAAAA==.Wazwaz:BAAANQAECgEIAQABNQAECggILQAPABslAA==.',
Wi='Wildbill:BAAANQAECgIIAwAAAA==.Willîe:BAAANQAECgMICQAAAA==.Wingsofsteel:BAAANQABCgQIBAAAAA==.Winstagram:BAAANQADCgQIBAAAAA==.',
Wo='Wolnir:BAAANQADCgUICQAAAA==.Wombshifter:BAAANQAECgEIAQAAAA==.Wowiezonk:BAAANQABCgIIAgAAAA==.',
Xe='Xeracia:BAAANQADCggIFgAAAA==.Xerethis:BAAANQADCgcIDAAAAA==.',
Xi='Xibaba:BAAANQAECgEIAQAAAA==.',
Xs='Xshirroz:BAAANQADCggICAAAAA==.',
Yo='Yogí:BAABNQAECn8xAAIWAAoKMBchCABzAQAWAAoKMBchCABzAQAAAA==.Yokos:BAAANQADCgMIAwAAAA==.',
Yu='Yunkali:BAAANQADCgcIDAAAAA==.',
Za='Zahneel:BAAANQAECggIDgAAAA==.Zarallia:BAAANQAECgQIBQAAAA==.Zaratul:BAACNQAFFH8LAAILAAQKCB73DgBdAQALAAQKCB73DgBdAQA1AAQKfzIAAgsACgoTJE0NAJkDAAsACgoTJE0NAJkDAAAA.Zarisong:BAAANQAECggICwAAAA==.',
Zh='Zhawaricus:BAAANQAECgQIBgAAAA==.Zhuri:BAAANQABCgcICwAAAA==.',
Zo='Zoburg:BAAANQAECgUIBAABNQAECgcIJAABANwiAA==.',
Zp='Zpig:BAAANQAECggICAABNQAECggICAAIAAAAAA==.',
Zu='Zugssico:BAAANQADCgYIBgAAAA==.',
Zy='Zyrian:BAAANQAECgEIAQAAAA==.',
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
