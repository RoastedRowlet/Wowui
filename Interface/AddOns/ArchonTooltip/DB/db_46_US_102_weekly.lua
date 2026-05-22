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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Paladin-Retribution','Paladin-Protection','Mage-Frost','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Fury','Hunter-Survival','Warrior-Protection','Warrior-Arms','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Unholy','Priest-Holy','DemonHunter-Devourer','Monk-Windwalker','DemonHunter-Vengeance','Druid-Balance','Mage-Arcane','Hunter-Marksmanship','Priest-Discipline','Mage-Fire','DeathKnight-Blood','Monk-Mistweaver','Priest-Shadow','DemonHunter-Havoc','DeathKnight-Frost','Paladin-Holy','Druid-Feral',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abortheira:BAAALgADCgUJBQAAAA==.',
Ac='Acelord:BAABLgAECn8XAAIBAAkJkhGBMwC8AQABAAkJkhGBMwC8AQAAAA==.Actaeon:BAAALgAECgMJAwAAAA==.',
Ad='Adaar:BAAALgAECgEJAQAAAA==.Adakat:BAAALgADCgEJAQAAAA==.Adanthedark:BAAALgADCgIJAgAAAA==.Adariom:BAAALgADCgUJCAAAAA==.Adrian:BAAALgADCgEJAQAAAA==.Adriannos:BAAALgAECgEJAQAAAA==.',
Ae='Aethir:BAAALgADCgYJBwAAAA==.',
Ag='Agonyy:BAAALgAECgUJDQAAAA==.Agrias:BAAALgADCgEJAQAAAA==.',
Ah='Aharadack:BAAALgADCgUJCwAAAA==.',
Ak='Akawaka:BAAALgAECgEJAQAAAA==.Akiji:BAAALgADCgEJAQAAAA==.Akimurad:BAAALgAECgYJBgAAAA==.',
Al='Alakazam:BAAALgADCgcJBwAAAA==.Alanie:BAAALgADCggJCAABLgAECggJIwACABUeAA==.Ald:BAAALgAECgEJAgAAAA==.Aldebaraum:BAAALgAECgEJAgAAAA==.Alexextreme:BAAALgAECgcJEQAAAA==.Alikth:BAAALgADCgYJBgAAAA==.Alista:BAAALgAECgMJAgAAAA==.Allandyr:BAABLgAECn8rAAIBAAgJkhYNMgDCAQABAAgJkhYNMgDCAQAAAA==.Alvarao:BAAALgAECgQJBAAAAA==.',
Am='Amandadark:BAAALgAECgEJAQAAAA==.Amano:BAAALgADCgYJDAAAAA==.',
An='Anaxthacia:BAAALgADCgMJAwAAAA==.Andinth:BAAALgADCgQJBAAAAA==.Andrepvp:BAAALgADCggJDwAAAA==.Andrit:BAAALgADCgEJAQAAAA==.Angelloz:BAABLgAECn8mAAIDAAgJxRDPWQB1AQADAAgJxRDPWQB1AQAAAA==.Anjelvs:BAAALgAECgYJBgAAAA==.Annaoh:BAABLgAECn8cAAIDAAgJVB2RJgAgAgADAAgJVB2RJgAgAgAAAA==.Annia:BAAALgADCgYJBwAAAA==.Anãodengoso:BAABLgAECn8pAAMDAAgJSCa2EgCYAgADAAgJSCa2EgCYAgAEAAIJIxKyLABoAAABLgAECggJKQADAEgmAA==.',
Ap='Apökalÿpsïs:BAABLgAECn8UAAIFAAYJNAqfnwACAQAFAAYJNAqfnwACAQAAAA==.',
Ar='Arator:BAAALgAECgYJBgAAAA==.Ardry:BAAALgADCgYJBgAAAA==.Argaloth:BAAALgAECgYJBwAAAA==.',
As='Ashthon:BAABLgAECn8cAAIBAAcJgxx8NAC4AQABAAcJgxx8NAC4AQAAAA==.Asmitta:BAAALgADCgQJBAAAAA==.',
At='Atomictank:BAAALgAECgYJEgAAAA==.Atonos:BAAALgAECgEJBAAAAA==.',
Au='Augustosg:BAAALgAECgEJAgABLgAECgQJCQAGAAAAAA==.Auquenai:BAAALgADCgUJBQAAAA==.Aurielis:BAAALgAECgEJAgAAAA==.',
Av='Averagemage:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAAALgAECgQJBAAAAA==.',
Az='Azadium:BAAALgAECgUJCQAAAA==.Azul:BAAALgAECgMJBAAAAA==.',
Ba='Badayaga:BAAALgADCgIJAgAAAA==.Bakunogrind:BAAALgAECgUJBQABLgAFFAQJBwAHAEMeAA==.Balthar:BAABLgAECn8gAAQIAAcJOhKsMgAYAQAIAAcJoxGsMgAYAQAJAAQJChFrHQD1AAAHAAQJBg+FeAB5AAAAAA==.Barcaldas:BAAALgAECgUJBgAAAA==.Barrocø:BAAALgAECgQJBQABLgAECgcJDwAGAAAAAA==.Basara:BAAALgAECgYJCQAAAA==.Batefraco:BAAALgADCgIJAgAAAA==.',
Bb='Bbiel:BAABLgAECn8hAAMKAAUJwBXtDwD0AAAKAAUJwBXtDwD0AAALAAEJ3wFGFwEfAAAAAA==.',
Be='Beelgarath:BAAALgAECgEJAQAAAA==.Beherit:BAAALgADCgMJBwAAAA==.Beliall:BAAALgADCgQJBQAAAA==.Belowlight:BAAALgADCgYJCwAAAA==.Belttazar:BAAALgADCgkJDwAAAA==.Bemmaith:BAAALgAECgQJBAAAAA==.Berzan:BAAALgAECgQJBwAAAA==.Beyoond:BAACLgAFFH8NAAMLAAMJBhb4YgCtAAALAAIJcRr4YgCtAAAMAAEJMA3+EQBLAAAuAAQKfzcABAsACQmIHGYZAFECAAsACQmJG2YZAFECAAoABAm3D+cxAPEAAAwAAwnBFqoRANQAAAAA.',
Bi='Bielinski:BAAALgAECgQJBAAAAA==.',
Bl='Blackdut:BAAALgAECgQJBwAAAA==.Blackrøse:BAAALgADCgYJBgAAAA==.Blackteriaa:BAAALgAECgUJDwAAAA==.Blacrapumzel:BAAALgAECgMJAwAAAA==.Blankis:BAAALgADCgYJCQAAAA==.Blizther:BAAALgADCgIJAgAAAA==.Bloodh:BAAALgAECgEJAwAAAA==.Bls:BAAALgADCgMJAwAAAA==.',
Bo='Boijf:BAAALgADCgEJAQAAAA==.Boladomal:BAAALgAECgMJAwAAAA==.Bones:BAAALgAECgEJAQAAAA==.Boromy:BAAALgAECgEJAgAAAA==.Boruck:BAAALgAECgIJAwAAAA==.',
Br='Braandom:BAAALgAECgcJDAAAAA==.Bradan:BAABLgAECn8eAAINAAgJURWcKgAOAgANAAgJURWcKgAOAgAAAA==.Brandomm:BAAALgAECgUJDAAAAA==.Branmir:BAAALgAECgMJBgAAAA==.Bridda:BAAALgAECgYJDAAAAA==.Brolho:BAAALgADCgEJAQAAAA==.Bruzapaladin:BAAALgADCgUJBQAAAA==.',
Bt='Btrcaotics:BAAALgAECgIJBgAAAA==.Btrguard:BAAALgAECgIJAgAAAA==.',
['Bé']='Béto:BAAALgAECgMJBAAAAA==.',
['Bí']='Bíbs:BAABLgAECn8VAAIBAAgJkRMLMwC+AQABAAgJkRMLMwC+AQAAAA==.',
Ca='Cabanagé:BAAALgAECgUJBwAAAA==.Cabeludometa:BAAALgADCgEJAQAAAA==.Cabodecobre:BAAALgAECgUJCwAAAA==.Cainmarko:BAAALgAECgYJEAAAAA==.Caiowisk:BAAALgAECgYJDQAAAA==.Calir:BAAALgADCgYJFgAAAA==.Calçadora:BAABLgAECn81AAIOAAkJtiCyAwDIAgAOAAkJtiCyAwDIAgAAAA==.Cardrok:BAAALgADCgEJAQAAAA==.Caridosa:BAAALgADCgUJBQAAAA==.Carnius:BAABLgAECn9BAAQPAAgJRh5WCgABAgAPAAgJIR1WCgABAgANAAIJuiCWagBSAAAQAAEJDxzyRgBGAAAAAA==.Casipala:BAAALgAECgEJAQAAAA==.Casuall:BAAALgAECgcJBwAAAA==.Cataclysm:BAAALgAECgMJBAAAAA==.Catalango:BAAALgAECgQJCgAAAA==.Catapó:BAAALgAECgQJCQAAAA==.Catapózão:BAABLgAECn8mAAICAAgJ8h6hFgBLAgACAAgJ8h6hFgBLAgAAAA==.Catü:BAAALgAECgEJAQAAAA==.Cavernus:BAAALgADCgMJAwAAAA==.Caves:BAAALgADCgIJAgAAAA==.Caveston:BAAALgADCgUJCgAAAA==.',
Cb='Cbestabr:BAAALgADCgYJBgAAAA==.',
Ch='Chamadmordor:BAAALgAECgMJBQAAAA==.Charats:BAAALgADCgYJDQAAAA==.Charterine:BAAALgADCgYJBgAAAA==.Chaya:BAAALgADCgUJBQAAAA==.Chicknorris:BAAALgADCgUJBQAAAA==.Chifrudaxl:BAAALgAECgMJAwAAAA==.Chrisjks:BAAALgADCgYJCgAAAA==.',
Ci='Cindyn:BAAALgAECgEJAQAAAA==.',
Cl='Clared:BAAALgADCgEJAQAAAA==.Clebeya:BAAALgADCgQJBAAAAA==.Climps:BAAALgAECgcJDwAAAA==.',
Co='Cobyx:BAAALgADCgcJDAAAAA==.Cocaferoz:BAAALgADCgEJAQAAAA==.Coffeeaddict:BAAALgADCgMJAwAAAA==.Colugo:BAAALgADCgIJAgAAAA==.Coriisco:BAAALgADCgIJAgAAAA==.Corollaxei:BAABLgAECn8rAAMRAAkJpxa4CAAZAgARAAkJpxa4CAAZAgASAAEJBQZWeAAhAAAAAA==.Cosculluela:BAAALgADCgUJBwAAAA==.',
Cr='Creuzapriest:BAAALgAECgEJAQAAAA==.Crookedyoung:BAAALgAECgEJAwABLgAECgUJCwAGAAAAAA==.Cruzade:BAAALgAECgUJCwABLgAFFAEJAQAGAAAAAA==.Cröwllëy:BAABLgAECn8eAAITAAgJtxbjPQDEAQATAAgJtxbjPQDEAQAAAA==.',
Cu='Cubatao:BAABLgAECn8UAAIBAAYJUxTlVgBEAQABAAYJUxTlVgBEAQAAAA==.Cucaracha:BAAALgAECgUJCgAAAA==.',
Da='Dahhak:BAAALgAECgUJCAAAAA==.Dakhgagul:BAAALgADCgUJBQAAAA==.Dakshayani:BAAALgAECgEJAQAAAA==.Danielbrz:BAAALgAECgMJAwAAAA==.Danygatuxa:BAAALgAECgUJCQAAAA==.Dardano:BAAALgADCgcJCwAAAA==.Daree:BAAALgAECgEJAQAAAA==.Darkenes:BAAALgAECgEJAQAAAA==.Darkinmt:BAAALgADCgcJCAAAAA==.Darknesstk:BAAALgAECgQJCQAAAA==.Darksiderptc:BAAALgADCgcJDwAAAA==.Darthmansur:BAAALgAECgMJAwAAAA==.',
De='Deadvi:BAAALgAECgcJDwAAAA==.Deadziin:BAAALgAECgYJDAAAAA==.Demetrix:BAAALgADCgkJCgAAAA==.Dennyam:BAAALgAECgYJCQAAAA==.Derothey:BAABLgAECn8jAAIFAAcJgxSoZAB0AQAFAAcJgxSoZAB0AQAAAA==.Deulorem:BAACLgAFFH8IAAIUAAQJjBJuDwAFAQAUAAQJjBJuDwAFAQAuAAQKfygAAhQACQn2F4kKAHMCABQACQn2F4kKAHMCAAAA.Devilblade:BAABLgAECn8RAAIVAAgJXgmljwACAQAVAAgJXgmljwACAQAAAA==.',
Di='Diabolynn:BAAALgAECgQJBAAAAA==.',
Dk='Dkatraia:BAAALgAECgMJAwAAAA==.',
Dn='Dngfafinir:BAAALgAECggJBAABLgAFFAQJCgADAFgXAA==.Dnghidan:BAACLgAFFH8KAAIDAAQJWBfgHgBJAQADAAQJWBfgHgBJAQAuAAQKfygAAgMACQmrHvohAKICAAMACQmrHvohAKICAAAA.Dngtobi:BAAALgAECgUJBQABLgAFFAQJCgADAFgXAA==.',
Do='Dollynhø:BAABLgAECn8dAAIWAAgJARoREAD6AQAWAAgJARoREAD6AQAAAA==.Donyed:BAAALgAECgQJBAAAAA==.Dottado:BAAALgADCgcJCgAAAA==.',
Dr='Drackah:BAAALgADCgcJBwAAAA==.Draconían:BAAALgAECgEJBgAAAA==.Dracón:BAAALgADCgkJDwAAAA==.Draigo:BAAALgAECgIJAgAAAA==.Dreykar:BAABLgAECn8kAAMVAAgJHxVTNQCmAQAVAAgJHxVTNQCmAQAXAAEJ2BzIHwBQAAAAAA==.Drogorn:BAAALgAECgUJCwAAAA==.Druidaezeki:BAAALgADCgYJCwAAAA==.Druidjm:BAAALgADCgMJAwAAAA==.Druvannar:BAAALgADCgEJAQAAAA==.',
Du='Dultrasenegl:BAABLgAECn8dAAIBAAYJAA3yZQA2AQABAAYJAA3yZQA2AQAAAA==.Dunois:BAAALgAECgIJBgAAAA==.',
['Dä']='Dähäkä:BAABLgAECn8WAAIDAAgJYRi4OgDPAQADAAgJYRi4OgDPAQAAAA==.',
Ed='Edven:BAACLgAFFH8LAAIRAAMJcwINGgCSAAARAAMJcwINGgCSAAAuAAQKfyEAAhEABgnKDMYlAEgBABEABgnKDMYlAEgBAAAA.',
El='Eldros:BAAALgAECgYJCAAAAA==.Elementais:BAAALgAECgQJBwAAAA==.Elgado:BAAALgAECgEJAwAAAA==.Elgatadexota:BAAALgADCgkJCgAAAA==.Eliksir:BAAALgAECgUJBQAAAA==.Ellanor:BAABLgAECn8cAAIFAAgJ+hgxOwDrAQAFAAgJ+hgxOwDrAQAAAA==.Elruth:BAAALgADCggJCAABLgAFFAQJCAAUAIwSAA==.Eltão:BAAALgADCgEJAQAAAA==.Elunah:BAAALgADCgQJBAAAAA==.Elwindor:BAAALgAECgEJAQAAAA==.Elyind:BAAALgADCgYJBgAAAA==.',
Em='Emmymm:BAAALgADCgIJAgAAAA==.',
En='Endeavour:BAAALgADCgEJAQAAAA==.Enegadiel:BAABLgAECn8cAAIDAAcJIg+pbQBHAQADAAcJIg+pbQBHAQAAAA==.Enoia:BAAALgADCgUJBQAAAA==.',
Eq='Equidnah:BAAALgAECgIJAgAAAA==.',
Er='Erickya:BAAALgAECgYJCQAAAA==.Ervadocè:BAABLgAECn8ZAAIYAAYJwhiaJABKAQAYAAYJwhiaJABKAQAAAA==.Ervelino:BAAALgAECgMJBAAAAA==.',
Es='Estrogosbald:BAABLgAECn8UAAIZAAgJfgk3BQBJAQAZAAgJfgk3BQBJAQAAAA==.',
Ev='Evely:BAABLgAECn8aAAIaAAcJgxjvCQCEAQAaAAcJgxjvCQCEAQAAAA==.',
Ex='Exarch:BAACLgAFFH8KAAIOAAQJEBTkCQBSAQAOAAQJEBTkCQBSAQAuAAQKfyEAAg4ACAlPHAYIAGQCAA4ACAlPHAYIAGQCAAAA.',
Fa='Faengar:BAAALgAECgUJCAAAAA==.Falcondk:BAAALgAECgEJAQAAAA==.Falconess:BAAALgADCgEJAQAAAA==.',
Fe='Feathria:BAAALgAECgMJAwAAAA==.Felipebritoo:BAAALgAECgMJBgABLgAECgYJBwAGAAAAAA==.Fenrirsp:BAAALgAFFAIJAwAAAA==.Ferdruiid:BAAALgADCgkJEwAAAA==.Feropudo:BAAALgADCgkJDgAAAA==.Ferrarig:BAAALgAECgEJBAAAAA==.',
Fi='Figy:BAAALgAECgQJBAAAAA==.',
Fl='Flemma:BAABLgAECn8YAAIRAAgJJgd9FgAaAQARAAgJJgd9FgAaAQAAAA==.Flexer:BAAALgAECgEJAQAAAA==.Flores:BAAALgADCgMJBQAAAA==.Floridastyle:BAABLgAECn8dAAIbAAUJTxYQJgA/AQAbAAUJTxYQJgA/AQAAAA==.',
Fo='Foguerosa:BAACLgAFFH8JAAMFAAMJpRyQLwD4AAAFAAMJpRyQLwD4AAAcAAEJggBxAwA7AAAuAAQKfxYAAgUACAloIYM0AAUCAAUACAloIYM0AAUCAAAA.Folghunthir:BAAALgADCgQJBAAAAA==.',
Fr='Frankkquini:BAAALgADCgYJEgAAAA==.Friodokrl:BAABLgAECn8tAAMdAAkJNx03CABIAgAdAAkJLRs3CABIAgATAAcJXxhfSQCfAQAAAA==.Fritzgerhart:BAAALgAECgEJAQAAAA==.Frostmhaw:BAAALgADCgUJBQAAAA==.Frostreaper:BAAALgAECgQJBgAAAA==.',
Fu='Fubukiofhell:BAAALgAECgYJEgAAAA==.Fuginzao:BAAALgAECgEJAQAAAA==.Furtacor:BAAALgADCgcJBwAAAA==.Furyarh:BAAALgAECgMJAwAAAA==.',
['Fí']='Fí:BAAALgADCggJDgABLgAECgkJHQABAK8aAA==.',
Ga='Gabana:BAAALgADCgQJBAAAAA==.Gabdobbuh:BAAALgAECgUJCAAAAA==.Gabn:BAAALgAECgIJAwAAAA==.Gafgar:BAAALgADCgUJCQAAAA==.Gaila:BAAALgAECgIJBQAAAA==.Galduin:BAABLgAECn8rAAINAAkJ5xPpEwAHAgANAAkJ5xPpEwAHAgAAAA==.Gallymonk:BAAALgAECgcJDQAAAA==.',
Ge='Gedexx:BAAALgAECgMJAgAAAA==.Geduntruppa:BAAALgAECgYJBgAAAA==.Gentioiroh:BAAALgAECgMJAwAAAA==.',
Gh='Ghorderp:BAAALgADCgcJDAAAAA==.Ghosstt:BAAALgAECgEJAgAAAA==.Ghoulrozon:BAAALgADCgYJBgAAAA==.',
Gi='Giovannapala:BAABLgAECn8UAAIDAAcJhg6QggAeAQADAAcJhg6QggAeAQAAAA==.Giripoca:BAAALgAECgQJCQAAAA==.',
Gl='Gladsmonge:BAABLgAECn8cAAIeAAcJCx3SFgALAgAeAAcJCx3SFgALAgAAAA==.Glorcckk:BAAALgAECgMJAwAAAA==.',
Gn='Gnomagga:BAAALgAECgcJEAABLgAECggJMwAEAB8cAA==.Gnomohabe:BAAALgADCgQJBgAAAA==.',
Go='Goddofwarr:BAAALgADCggJEQAAAA==.Gonb:BAAALgADCgUJBQAAAA==.Goueki:BAABLgAECn8kAAMBAAgJGxeaKQDnAQABAAgJGxeaKQDnAQAaAAIJSwEtgwA8AAAAAA==.',
Gr='Greenzle:BAAALgAECgIJAgAAAA==.Grillnborst:BAAALgADCgEJAgAAAA==.Grilonp:BAAALgADCgQJCAAAAA==.Grogtixa:BAAALgAECggJCQABLgAECgkJKgAIAFgWAA==.Gromoff:BAABLgAFFH8FAAILAAIJuh9nZACoAAALAAIJuh9nZACoAAAAAA==.Grunmonk:BAAALgADCgEJAQAAAA==.Grømmar:BAAALgADCgMJAwAAAA==.',
Gu='Gudangara:BAAALgADCgYJBgAAAA==.Gumy:BAAALgAECgEJAgAAAA==.Guztaverdead:BAAALgADCgQJBAAAAA==.',
['Gü']='Güistrong:BAAALgADCgIJAwAAAA==.',
Ha='Haakaí:BAAALgAECgUJCQAAAA==.Hackterin:BAAALgADCgYJBgAAAA==.Hadorah:BAAALgAECgUJBgAAAA==.Haerys:BAAALgADCgYJBgAAAA==.Handhemirr:BAAALgAECgMJBAAAAA==.Harany:BAABLgAECn8UAAMbAAcJPAgpOwC0AAAbAAcJPAgpOwC0AAAfAAQJaQcdRACjAAAAAA==.Harrypotinho:BAABLgAECn8lAAILAAcJiRiuPgCiAQALAAcJiRiuPgCiAQAAAA==.Haunexd:BAAALgADCgMJAwAAAA==.Havenna:BAAALgAECgUJCAAAAA==.',
He='Headøhunter:BAAALgAECgEJAgAAAA==.Healgate:BAAALgAECgEJAQAAAA==.Heeythaly:BAAALgADCgcJCwAAAA==.Hellenah:BAAALgADCggJCAAAAA==.Herika:BAAALgADCgMJAwAAAA==.',
Ho='Hoem:BAAALgAECgMJAwAAAA==.Holand:BAAALgAECgYJDgAAAA==.Holydread:BAAALgAECgIJAgAAAA==.',
Hu='Hulig:BAABLgAECn8jAAIDAAgJKR3LIQA6AgADAAgJKR3LIQA6AgAAAA==.',
['Hø']='Høkulani:BAABLgAECn8VAAIFAAcJYxBkbABjAQAFAAcJYxBkbABjAQAAAA==.',
Ib='Ibuprofens:BAAALgAECgEJAQAAAA==.',
Ik='Ikiam:BAAALgAECgQJBQAAAA==.Ikslawok:BAAALgADCgYJEAAAAA==.',
Il='Ileria:BAAALgAECgYJBwAAAA==.Illarion:BAAALgADCgQJBAAAAA==.Illidanos:BAABLgAECn8ZAAIgAAgJCxDYFQB0AQAgAAgJCxDYFQB0AQAAAA==.Illidansan:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Illidris:BAAALgAECgUJBQAAAA==.Illumiinated:BAAALgAECgYJEQAAAA==.',
In='Incarus:BAAALgAECgcJCgAAAA==.Indis:BAAALgADCgQJBgAAAA==.Interst:BAAALgAECgEJAQAAAA==.',
Ir='Irion:BAAALgADCgkJJgAAAA==.',
Is='Iscalio:BAAALgAECgUJCAAAAA==.',
Iv='Ivinhosilva:BAAALgADCgYJBgAAAA==.',
Ja='Jackdawnsong:BAAALgAECgEJAwAAAA==.Jaene:BAAALgADCgYJCQAAAA==.Jahuun:BAAALgAECgcJDQAAAA==.Jamantoso:BAAALgAECgEJAQAAAA==.',
Je='Jeess:BAAALgADCgMJAwAAAA==.Jefflich:BAABLgAECn8eAAMTAAgJRgqUiQBuAQATAAgJ8QiUiQBuAQAhAAEJhxL0IQAyAAAAAA==.',
Jg='Jg:BAAALgAECgUJBwABLgAECgYJDgAGAAAAAA==.',
Ji='Jinknu:BAAALgAECgIJBAAAAA==.',
Jo='Jottapeg:BAAALgADCgcJAwAAAA==.',
Ju='Jubard:BAAALgADCgkJDAAAAA==.Juliamarques:BAAALgAECgMJBAAAAA==.',
['Jü']='Jüllÿe:BAAALgADCgEJAQAAAA==.',
Ka='Kaaellthas:BAAALgAECgQJCQAAAA==.Kacolux:BAAALgADCgEJAQAAAA==.Kaisaargente:BAAALgAECgEJAQAAAA==.Kakarotho:BAAALgAECgMJCQAAAA==.Kaldonios:BAAALgADCgcJEgAAAA==.Kamasutram:BAAALgADCgYJCwAAAA==.Kanadriel:BAAALgAECgcJCQAAAA==.Kanarinho:BAABLgAECn8pAAICAAkJIh+cBQAsAwACAAkJIh+cBQAsAwAAAA==.Karmussie:BAAALgADCgEJAQAAAA==.Katari:BAAALgAECgQJBAABLgAECgkJGwAiAJAeAA==.Kazandra:BAAALgADCgYJBgAAAA==.',
Ke='Kendars:BAABLgAECn8VAAQYAAYJ0xKfSAAKAQAYAAUJJhKfSAAKAQACAAUJFQ+5dgDzAAAjAAEJhRVNLgBCAAABLgAECgcJFgAdAHQXAA==.Ket:BAAALgADCgMJAwAAAA==.',
Kh='Khanmir:BAAALgAECgMJBgAAAA==.Khild:BAAALgAECgYJDQAAAA==.Khonar:BAAALgADCgUJBgAAAA==.',
Ki='Killerdek:BAAALgAECgUJBQAAAA==.Killshoty:BAAALgAECgEJAgAAAA==.',
Kl='Klissera:BAAALgADCgIJAgAAAA==.Kluzlocak:BAABLgAECn8iAAIbAAYJUQxQKQApAQAbAAYJUQxQKQApAQAAAA==.',
Kn='Knnabys:BAAALgAECgEJAQAAAA==.',
Ko='Komah:BAAALgAECgEJAQAAAA==.Korav:BAAALgAECgMJCQAAAA==.Korium:BAAALgADCgUJBQABLgAECgkJKgAPACAgAA==.Koruno:BAAALgADCgYJBgAAAA==.',
Kr='Krosn:BAAALgAECgEJAQAAAA==.Krozhul:BAAALgAECgQJBwAAAA==.',
Ku='Kurnous:BAAALgAECgEJAQAAAA==.Kutirenzo:BAAALgADCgUJBwAAAA==.',
La='Lafiel:BAAALgAECgcJEQAAAA==.Lamelo:BAAALgADCgYJBgAAAA==.Lanmo:BAAALgAECgcJAgAAAA==.Largatixazul:BAAALgADCgUJBgAAAA==.Lataria:BAAALgADCgEJAQAAAA==.Laurea:BAAALgAECgYJBgABLgAECgkJGwAiAJAeAA==.',
Le='Leebron:BAAALgAECgUJCQAAAA==.Lefthalas:BAAALgAECgUJCgAAAA==.Leitchero:BAAALgAECgIJAgAAAA==.Lemaz:BAAALgAECgEJAQAAAA==.Leonelmessi:BAAALgAFFAQJAQAAAA==.Lesco:BAAALgADCgMJAwAAAA==.',
Li='Lianele:BAAALgAECgIJAwAAAA==.Liaras:BAABLgAECn8pAAMUAAgJXRdGFADqAQAUAAgJXRdGFADqAQAfAAIJzABFaQAmAAAAAA==.Libertinagem:BAAALgAECgUJBQAAAA==.Lichtbaum:BAAALgAECgcJEwAAAA==.Lightsertrop:BAAALgADCgIJAgAAAA==.Liifecomm:BAACLgAFFH8KAAIUAAQJSxedCgA/AQAUAAQJSxedCgA/AQAuAAQKfzEAAhQACQniHVkNAIICABQACQniHVkNAIICAAAA.Liike:BAAALgAECgEJAQAAAA==.Linestra:BAAALgADCgUJBQAAAA==.Liniak:BAAALgAECgUJCwAAAA==.Lisong:BAAALgADCgUJBQAAAA==.Littlepurple:BAACLgAFFH8JAAIVAAMJzxJ7GwD2AAAVAAMJzxJ7GwD2AAAuAAQKfyQAAhUACQl0HJwYAMICABUACQl0HJwYAMICAAAA.',
Lo='Longhai:BAAALgADCgUJCAAAAA==.Lookatmylock:BAABLgAECn8dAAMKAAYJYhtxCAB1AQAKAAYJYhtxCAB1AQALAAIJRQmhBQFRAAAAAA==.Lordpain:BAAALgAECgcJDQAAAA==.Lortherti:BAAALgADCgUJBgAAAA==.Lorwin:BAAALgAECgcJEwAAAA==.Lotusbr:BAAALgADCgEJAQAAAA==.Louisenacioo:BAAALgAECgYJDgAAAA==.Loátrak:BAAALgADCgMJAwAAAA==.',
Lu='Luccablack:BAAALgAECgMJAwAAAA==.Lucyx:BAAALgAECgEJAQAAAA==.Luidar:BAAALgAECgQJBAAAAA==.Lukaslions:BAAALgAECgcJDgAAAA==.Lunarie:BAAALgAECgYJEwABLgAECgcJBwAGAAAAAA==.Luphoe:BAABLgAECn8iAAMCAAcJ9RzHJwAWAgACAAcJ9RzHJwAWAgAYAAQJkw4MSACVAAAAAA==.Luxanä:BAAALgADCggJDQAAAA==.',
['Lé']='Léio:BAAALgADCgcJCAAAAA==.Léora:BAAALgADCgIJAgAAAA==.',
['Lø']='Lørdsith:BAAALgAECgYJCAABLgAECggJBgAGAAAAAA==.',
['Lÿ']='Lÿcäns:BAAALgADCgMJAwAAAA==.',
Ma='Madagalux:BAAALgAECgUJEwAAAA==.Madjack:BAAALgAECgMJAwAAAA==.Madushi:BAAALgAECgIJAgAAAA==.Magatiun:BAAALgADCgMJBAAAAA==.Magogunt:BAABLgAECn8dAAIFAAkJMxGLOAD1AQAFAAkJMxGLOAD1AQAAAA==.Maguul:BAAALgAECgYJEQAAAA==.Magzifeh:BAABLgAECn8UAAIBAAcJ3SD2IAASAgABAAcJ3SD2IAASAgAAAA==.Mahadevi:BAAALgADCgIJAgAAAA==.Malandrvs:BAAALgAFFAEJAwAAAA==.Maljamim:BAAALgADCgIJAgAAAA==.Mamuthwar:BAABLgAECn8ZAAMNAAcJnRgeNgDQAQANAAcJnRgeNgDQAQAQAAEJMQ7ZQQA1AAAAAA==.Mandingavudu:BAAALgAECgEJAgABLgAECgcJCQAGAAAAAA==.Manei:BAAALgAECgMJAwAAAA==.Mangalarga:BAAALgADCgEJAQAAAA==.Manmoden:BAAALgADCgUJBQABLgAECgcJCQAGAAAAAA==.Mannatur:BAAALgAECgcJCQAAAA==.Manopaladino:BAAALgADCgYJBgAAAA==.Manowlo:BAAALgAECgMJAwAAAA==.Manzagon:BAAALgAECgQJBwABLgAECgcJCQAGAAAAAA==.Marmelo:BAAALgADCgQJBAAAAA==.Marretasanta:BAABLgAECn8kAAIDAAcJCRSsWgBzAQADAAcJCRSsWgBzAQAAAA==.Marù:BAAALgAECgYJCwAAAA==.Marúh:BAACLgAFFH8RAAIHAAQJMRt6FwA7AQAHAAQJMRt6FwA7AQAuAAQKfycAAgcACAnzIsQFABYDAAcACAnzIsQFABYDAAAA.Matroná:BAAALgADCggJBwAAAA==.Maxmorf:BAAALgADCgUJBQAAAA==.Mayarabr:BAAALgAECgIJAwAAAA==.Mazeratos:BAAALgAECgMJBAAAAA==.',
Mc='Mcorelhao:BAAALgADCgEJAQAAAA==.',
Me='Medoza:BAAALgAECgQJBQAAAA==.Megrezz:BAAALgAECgEJAQAAAA==.Mehiel:BAAALgAECgEJAQAAAA==.Mekihlvshtak:BAAALgAECgEJAQAAAA==.Meliøðas:BAAALgADCgEJAQAAAA==.Mendingu:BAAALgAECgcJDwAAAA==.Mercenarybr:BAAALgAECgEJAQAAAA==.Merumim:BAAALgAECgYJCwAAAA==.Metalgirl:BAAALgADCgYJCwAAAA==.',
Mi='Midrão:BAAALgAECgcJCQAAAA==.Mikasaackerr:BAAALgAECgEJAQAAAA==.Milczarek:BAAALgAECgEJAQAAAA==.Mindlocker:BAABLgAECn8XAAILAAYJ8gY3kwDWAAALAAYJ8gY3kwDWAAAAAA==.Minorus:BAAALgAECgcJEgAAAA==.Mistifs:BAABLgAECn8VAAIeAAgJGxkfEQAvAgAeAAgJGxkfEQAvAgAAAA==.',
Mo='Modogz:BAAALgADCgYJBgAAAA==.Momongadk:BAAALgADCgcJBwAAAA==.Monkeydking:BAAALgADCgUJBQAAAA==.Morania:BAAALgAECggJEQAAAA==.Mordekais:BAAALgAECgIJAgAAAA==.Morganne:BAAALgAECgEJAQAAAA==.Morinami:BAAALgADCgUJBQAAAA==.Moriyama:BAABLgAECn8jAAICAAcJtxs2IAD/AQACAAcJtxs2IAD/AQAAAA==.Morphisz:BAAALgAECgYJCQABLgAECgcJCQAGAAAAAA==.Morphiszs:BAAALgAECgMJBAABLgAECgcJCQAGAAAAAA==.Morphizs:BAAALgAECgEJAgABLgAECgcJCQAGAAAAAA==.Mortesan:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.',
Mp='Mpastor:BAAALgADCgUJBQAAAA==.',
Mu='Muca:BAAALgADCgEJAQAAAA==.Muho:BAAALgADCgEJAQAAAA==.Mukonha:BAABLgAECn8jAAILAAcJeA5NZAA4AQALAAcJeA5NZAA4AQAAAA==.',
['Mã']='Mãoleves:BAAALgADCgEJAQAAAA==.',
['Må']='Måximus:BAAALgAECgIJAgAAAA==.',
['Mü']='Müller:BAAALgADCgEJAQABLgAECgUJCwAGAAAAAA==.',
Na='Naeryndam:BAAALgADCgEJAQAAAA==.Narutowow:BAAALgADCgMJAwAAAA==.Natcmd:BAAALgADCggJDAAAAA==.Nayanna:BAAALgADCgcJDQAAAA==.',
Ne='Negblack:BAAALgAECgYJDAAAAA==.Neggi:BAAALgAECgUJBwAAAA==.Nemesysy:BAAALgAECgMJAwAAAA==.Nerphien:BAAALgADCgUJBQAAAA==.Nesktpally:BAAALgAECgcJCAAAAA==.Netbrood:BAAALgADCgUJBgABLgAECgUJBwAGAAAAAA==.Netbrother:BAAALgAECgUJBwAAAA==.Nethdorai:BAAALgADCgQJBAAAAA==.Netherbane:BAABLgAECn8ZAAMQAAcJ8BYFEQCKAQAQAAcJ8BYFEQCKAQANAAEJAAAmjAAAAAAAAA==.Nezuko:BAAALgADCgcJEQABLgAECgcJJQALAIkYAA==.',
Ni='Nightmære:BAAALgAECgQJCAAAAA==.Nikelok:BAAALgAECgMJAwAAAA==.Ninfador:BAABLgAECn8eAAIbAAYJgxeZIABrAQAbAAYJgxeZIABrAQAAAA==.Ninpus:BAAALgAECgMJAwAAAA==.',
No='Noobmasteer:BAAALgADCgIJAgAAAA==.Nooneknow:BAABLgAECn8rAAITAAgJ8SCjIABBAgATAAgJ8SCjIABBAgAAAA==.Nosios:BAAALgAECgYJBgAAAA==.Nosrede:BAAALgAECgEJAQAAAA==.Notz:BAAALgADCgMJBAAAAA==.',
Nu='Nuccixama:BAAALgAECgYJBgAAAA==.Nuriel:BAAALgAECgMJAwAAAA==.',
Ny='Nyde:BAAALgAECgMJAwAAAA==.',
['Nø']='Nøar:BAAALgADCgIJAgAAAA==.',
Oa='Oakshlar:BAAALgAFFAEJAQAAAA==.',
Oc='Ocelaris:BAAALgAECgEJAgAAAA==.',
Oh='Ohlu:BAAALgAECgQJBAAAAA==.Ohluh:BAAALgAECgcJDQAAAA==.',
Or='Oryana:BAAALgADCgcJIAAAAA==.Oríon:BAAALgADCgIJAgAAAA==.',
Ot='Otton:BAABLgAECn8aAAIDAAYJOwexrADWAAADAAYJOwexrADWAAAAAA==.',
Ov='Overnigth:BAAALgADCgIJAgAAAA==.Overwalker:BAAALgADCgIJAgAAAA==.Ovosemdente:BAAALgADCgEJAQAAAA==.',
Ow='Owllskull:BAAALgAECgYJBwAAAA==.',
Oz='Ozovo:BAAALgAECgcJDgAAAA==.',
Pa='Pacoka:BAAALgADCgQJBQAAAA==.Padrafferty:BAAALgADCgcJBwAAAA==.Paidesanto:BAAALgAECgYJEAAAAA==.Paidesantox:BAAALgAECgYJCgABLgAECgkJKwANAOcTAA==.Paladinokun:BAAALgAECgEJAQAAAA==.Palanis:BAAALgAECgcJBwAAAA==.Palazarta:BAAALgAECgcJEAAAAA==.Pandavoli:BAAALgAECgUJCQAAAA==.Panky:BAAALgAECgQJBAAAAA==.Panquecudo:BAAALgADCgIJAgAAAA==.',
Pd='Pdois:BAAALgADCgMJAwAAAA==.',
Pe='Pesscador:BAAALgAECgMJAwAAAA==.Petrolesk:BAAALgAECgYJBwAAAA==.',
Pi='Piriguetee:BAAALgADCgEJAQAAAA==.Pirro:BAAALgAECgEJAQAAAA==.Pisadinha:BAAALgADCgcJBwAAAA==.',
Pk='Pkzimn:BAAALgADCgUJBQAAAA==.',
Pl='Playsson:BAAALgAECgYJEgAAAA==.Plottwist:BAAALgADCgcJDwABLgAECggJJwATAN8WAA==.',
Po='Pogonus:BAAALgADCgIJAgAAAA==.Pontocego:BAAALgAECgQJBAAAAA==.Posturado:BAAALgADCgEJAQAAAA==.Powerworth:BAAALgAECgEJAQAAAA==.',
Pr='Pravios:BAAALgAECgIJBAAAAA==.Priestkill:BAAALgADCgMJAgAAAA==.Primewolf:BAAALgAECgIJAgAAAA==.',
Pt='Pterodactilo:BAAALgAECgYJAQAAAA==.',
Pu='Puherito:BAAALgAECgQJCAAAAA==.Purgas:BAAALgAECgYJEwAAAA==.',
Qu='Quinthalam:BAAALgADCgMJAwAAAA==.',
Ra='Rafac:BAAALgADCgEJAQABLgAECggJCwAGAAAAAA==.Rafazinho:BAAALgADCgQJBAAAAA==.Ramyna:BAAALgAECgMJBQAAAA==.Ramyra:BAAALgADCgcJDQAAAA==.Raphaeldh:BAAALgAECgEJAgAAAA==.Raphahunterr:BAAALgADCgEJAQAAAA==.Raposa:BAAALgADCgEJAQAAAA==.Raposinha:BAAALgADCgMJAwAAAA==.Rarkway:BAAALgAECgcJCwAAAA==.Ravenblak:BAAALgADCgEJAQAAAA==.Rayanne:BAAALgADCgYJBgAAAA==.',
Re='Reckfull:BAAALgAECgYJBgAAAA==.Regininha:BAAALgAECgEJAQAAAA==.Reloumifrend:BAAALgAECgcJCgAAAA==.Rendros:BAAALgADCgUJBQAAAA==.',
Rh='Rhaegaar:BAAALgAECgcJDQAAAA==.Rhanideri:BAAALgADCgEJAQAAAA==.Rhodinius:BAAALgAECgMJCAAAAA==.',
Ri='Rivotreel:BAAALgADCgQJBAAAAA==.',
Ro='Robeerth:BAAALgAFFAEJAQAAAA==.Rochera:BAAALgAECgEJAQAAAA==.Rokhanar:BAAALgAECgUJBgAAAA==.',
Ru='Rudemonster:BAAALgAECgEJAQAAAA==.Ruhtarr:BAAALgADCgEJAQAAAA==.',
Ry='Ryukato:BAAALgAECgQJBQAAAA==.',
Sa='Saek:BAAALgAECgcJEgAAAA==.Sanderclone:BAAALgAECgEJAQAAAA==.Sanguenafaca:BAAALgADCgYJBgAAAA==.Santiss:BAABLgAECn8WAAIDAAYJDhW3bwBDAQADAAYJDhW3bwBDAQAAAA==.Santorini:BAAALgAECgcJCwAAAA==.Saphirot:BAAALgADCgUJBQAAAA==.Saphis:BAAALgADCgEJAQAAAA==.Sardado:BAAALgAECgEJAQAAAA==.Sardron:BAAALgADCgMJAwAAAA==.',
Sc='Scanorr:BAAALgAECgEJAQAAAA==.Scheffers:BAAALgAECgUJBwAAAA==.',
Se='Selah:BAAALgADCgMJBQAAAA==.Selver:BAAALgAECgcJCAABLgAECggJDQAGAAAAAA==.Selüne:BAAALgAECgcJDQAAAA==.Sephora:BAAALgAECgYJCwABLgAECggJKQAUAF0XAA==.',
Sh='Shadowlock:BAAALgADCgIJAQABLgAECgYJDAAGAAAAAA==.Shadowmornac:BAAALgAECgIJAgAAAA==.Shamanica:BAAALgAECgEJAgAAAA==.Shamateus:BAAALgADCggJEwAAAA==.Shasuna:BAAALgADCgIJAgAAAA==.Shaunnun:BAAALgADCgEJAQAAAA==.Shenloong:BAAALgADCgYJBgAAAA==.Shinnók:BAAALgAECgIJAgAAAA==.Shiíro:BAAALgAECgMJBgABLgAFFAQJDAADAOcUAA==.Shynato:BAAALgADCgEJAQAAAA==.Shynock:BAAALgADCgEJAQAAAA==.Shãka:BAAALgADCgMJAwAAAA==.',
Si='Siladriel:BAAALgADCgMJAwAAAA==.Sirgonzo:BAAALgAECggJEAAAAA==.',
Sk='Skullexus:BAAALgAECgMJBAAAAA==.Skunkbr:BAAALgADCgEJAQAAAA==.',
Sl='Sleepychety:BAAALgAECgUJBgAAAA==.Slowsmoke:BAAALgADCgYJBwAAAA==.Slyfer:BAAALgADCgMJAwAAAA==.',
Sn='Snatzz:BAAALgADCgMJAgAAAA==.',
So='Soggoth:BAAALgADCgkJCQAAAA==.Solk:BAAALgAECgMJAwAAAA==.Sontarfury:BAAALgAECgEJAQAAAA==.Sorim:BAABLgAECn8aAAICAAYJYB/sHwAAAgACAAYJYB/sHwAAAgAAAA==.Soryan:BAABLgAECn8dAAICAAcJ4RRbLwCdAQACAAcJ4RRbLwCdAQAAAA==.Soulassassin:BAAALgADCgIJAwAAAA==.Soulhell:BAABLgAECn8bAAIbAAYJaxTxIgBYAQAbAAYJaxTxIgBYAQAAAA==.',
Sp='Spartanlofs:BAAALgADCgcJEQAAAA==.Spawndeath:BAAALgADCgEJAQAAAA==.',
Ss='Ssushii:BAAALgAECgEJAQAAAA==.',
St='Stigmata:BAAALgADCgcJCAAAAA==.Stixmixdk:BAAALgAFFAQJAgAAAA==.Straz:BAAALgADCgQJBAAAAA==.Strongman:BAAALgAECgYJBgAAAA==.Stx:BAAALgAECgEJAQAAAA==.',
Su='Subsdk:BAACLgAFFH8NAAITAAQJJw9kQQA1AQATAAQJJw9kQQA1AQAuAAQKfyAAAhMACAlIHGQ4ANgBABMACAlIHGQ4ANgBAAAA.Sunwalkers:BAAALgAECgUJBgAAAA==.',
Sy='Systeni:BAAALgADCgkJDQAAAA==.',
['Sø']='Søøssø:BAAALgAECgEJAQAAAA==.',
Ta='Taha:BAAALgAECgYJDgAAAA==.Taillys:BAAALgADCgMJBAAAAA==.Tainy:BAAALgAECgEJAQAAAA==.Takenaka:BAAALgADCgMJAwAAAA==.Tarez:BAAALgAECggJBgAAAA==.Tarfonir:BAAALgAECgYJCQAAAA==.Tavalira:BAAALgADCgYJBgAAAA==.',
Te='Tealen:BAAALgAECgEJAQAAAA==.Ted:BAAALgAECgcJDAAAAA==.Teiseken:BAAALgAECgcJBwAAAA==.Tempesfúria:BAAALgADCgIJAgAAAA==.Tenébria:BAAALgAECgcJBwAAAA==.Teratsemknk:BAAALgAECgUJBQAAAA==.',
Th='Tharnforge:BAAALgAECgEJAQAAAA==.Thejokker:BAABLgAFFH8FAAINAAMJWQBjMgBgAAANAAMJWQBjMgBgAAAAAA==.Thelaststorm:BAAALgAECgkJAwAAAA==.Themooster:BAAALgAFFAEJAQAAAA==.Thepickles:BAAALgADCgkJFAAAAA==.Thepunk:BAAALgAECgQJDgAAAA==.Thesindorei:BAAALgAECgEJAQAAAA==.Thintor:BAAALgADCgEJAQAAAA==.Thormento:BAABLgAECn8VAAIHAAcJkBHJPABZAQAHAAcJkBHJPABZAQAAAA==.',
Ti='Tigerblood:BAAALgADCgUJBQAAAA==.Tipooreeii:BAAALgADCgEJAQAAAA==.Titanicos:BAAALgADCgQJBAAAAA==.',
Tj='Tjhunter:BAABLgAECn8fAAIBAAgJnQpeSQCNAQABAAgJnQpeSQCNAQAAAA==.',
To='Tobbiy:BAAALgAFFAIJAwAAAA==.Toddyb:BAAALgAECgIJAgAAAA==.',
Tr='Tranh:BAAALgADCgkJFQAAAA==.Traxer:BAAALgADCgQJBAAAAA==.Tripäsecä:BAAALgAECgMJBgAAAA==.Troladora:BAABLgAECn8VAAIFAAYJqA5vkAAdAQAFAAYJqA5vkAAdAQAAAA==.',
Ts='Tsreis:BAAALgADCgEJAQAAAA==.',
Ty='Tyrandrisa:BAAALgADCgIJAQAAAA==.',
['Tá']='Tátu:BAAALgADCgMJAwAAAA==.',
Um='Ummetrodefio:BAAALgADCgEJAQAAAA==.',
Ut='Uthred:BAABLgAECn8nAAQTAAkJ+gaEdQAvAQATAAkJDgSEdQAvAQAhAAYJoARvDADrAAAdAAMJrgkRNgBqAAAAAA==.',
Va='Vaelryn:BAAALgAECgUJBwAAAA==.Valdemmon:BAAALgAECgEJAQAAAA==.Valororo:BAAALgAECgUJDAAAAA==.Vandlesh:BAAALgAECgYJDwAAAA==.Vardha:BAAALgADCgQJBAAAAA==.Varka:BAAALgADCgYJGQAAAA==.',
Ve='Velkharun:BAAALgAECgQJCwABLgAFFAEJAQAGAAAAAA==.Venatrin:BAAALgADCgkJCQAAAA==.Vexxv:BAABLgAECn8UAAITAAUJshqnigBrAQATAAUJshqnigBrAQAAAA==.Vexxz:BAAALgAECgYJBwAAAA==.',
Vi='Viquue:BAAALgADCgYJBgAAAA==.Vivisoft:BAAALgADCgMJAwAAAA==.',
Vo='Voidrb:BAAALgADCgcJBwABLgAECgcJDwAGAAAAAA==.Vovogamer:BAAALgADCgEJAQAAAA==.',
['Vò']='Vòxs:BAACLgAFFH8MAAMQAAQJFBCwEgDVAAAQAAMJdBKwEgDVAAANAAEJ9QgEOABEAAAuAAQKf0oAAxAACAk8JLYDAMQCABAABwnDJLYDAMQCAA0ABglHHoQuAPcBAAAA.',
Wa='Walkery:BAAALgADCgIJAgAAAA==.Wattari:BAABLgAECn8ZAAIPAAYJDgRUKwCUAAAPAAYJDgRUKwCUAAAAAA==.',
Wh='Whiteep:BAAALgADCgYJCAAAAA==.Whiteseraph:BAAALgADCgEJAQAAAA==.Whynchester:BAAALgADCgEJAQAAAA==.',
Wi='Windsailor:BAAALgADCggJDgAAAA==.Wiserys:BAABLgAECn8iAAMLAAYJjiDAMgDOAQALAAYJjiDAMgDOAQAMAAMJOQyiGwCXAAAAAA==.',
Wm='Wmarcão:BAAALgAECgYJEAAAAA==.',
Wo='Wolfiez:BAAALgAECgUJDAAAAA==.Wolfnwar:BAAALgAECgQJCgAAAA==.Wopz:BAAALgADCgUJBQAAAA==.Worq:BAAALgADCgYJBgAAAA==.',
Wq='Wqz:BAABLgAECn8VAAIBAAcJWhmTNgDUAQABAAcJWhmTNgDUAQAAAA==.',
Wu='Wunamuno:BAAALgADCgkJCQAAAA==.',
Xa='Xallatath:BAAALgADCgUJBQAAAA==.Xamela:BAAALgADCgMJAwAAAA==.Xamãna:BAAALgAECgQJCQAAAA==.',
Xe='Xevron:BAAALgAECgQJBAAAAA==.Xexnetw:BAAALgAECgQJBAAAAA==.Xexnew:BAABLgAECn8ZAAMdAAkJ9RrOCAA8AgAdAAkJ9RrOCAA8AgATAAEJaQcBJQEnAAAAAA==.',
Xi='Xidevill:BAAALgAECgIJBwAAAA==.Xinthorak:BAAALgADCgEJAgAAAA==.Xinzhou:BAAALgADCgQJCAAAAA==.Xiseth:BAAALgAECgEJAQAAAA==.Xixíca:BAAALgADCgUJBgAAAA==.',
Xm='Xmari:BAAALgAECgEJAQAAAA==.',
Xn='Xnyx:BAAALgADCgYJBgAAAA==.',
Xu='Xulaman:BAAALgAECgcJDgAAAA==.Xungodz:BAAALgADCgQJBAAAAA==.Xunxu:BAABLgAECn8ZAAMDAAYJdhMQhwBsAQADAAYJdhMQhwBsAQAiAAEJJgM2ngArAAAAAA==.',
Xy='Xynrath:BAAALgADCgMJAwAAAA==.',
['Xÿ']='Xÿon:BAAALgAECgEJAQAAAA==.',
Ya='Yannadcg:BAABLgAECn8rAAIUAAgJ+QscIgBqAQAUAAgJ+QscIgBqAQAAAA==.',
Yo='Youdie:BAABLgAECn8YAAIfAAgJhRLwKgCEAQAfAAgJhRLwKgCEAQAAAA==.',
Yu='Yulthuan:BAAALgADCgMJAwAAAA==.',
Yv='Yvernus:BAAALgAECgQJBgAAAA==.',
Yz='Yziepala:BAAALgAECgIJAgAAAA==.',
Za='Zaaraki:BAABLgAECn8nAAMTAAgJ3xbLVQDwAQATAAgJhRbLVQDwAQAdAAcJ/xJPHwAEAQAAAA==.Zarolho:BAABLgAECn8VAAIIAAYJSA5uSgCyAAAIAAYJSA5uSgCyAAAAAA==.',
Ze='Zenitsua:BAAALgAECgYJCQAAAA==.Zenzeluk:BAAALgAECgMJAwAAAA==.Zephiir:BAAALgAECgYJEwAAAA==.Zeryen:BAAALgAECgEJAQAAAA==.',
Zh='Zhunka:BAAALgADCgEJAQAAAA==.',
Zo='Zornak:BAAALgADCgUJBQAAAA==.',
Zz='Zzx:BAAALgADCgcJBwAAAA==.',
['Zé']='Zécasete:BAAALgADCgUJBwAAAA==.',
['Ál']='Álucard:BAAALgAECgcJDQAAAA==.',
['Ån']='Åntares:BAAALgADCgMJAwAAAA==.',
['Éy']='Éyga:BAAALgAECgEJAwAAAA==.',
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
