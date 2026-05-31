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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Paladin-Retribution','Paladin-Protection','Mage-Frost','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Hunter-Survival','Warrior-Protection','Warrior-Arms','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','DemonHunter-Devourer','Monk-Windwalker','DemonHunter-Vengeance','Druid-Balance','Mage-Arcane','Hunter-Marksmanship','Priest-Discipline','Mage-Fire','Monk-Mistweaver','Priest-Shadow','DemonHunter-Havoc','DeathKnight-Frost','Druid-Feral','Monk-Brewmaster','Paladin-Holy',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abortheira:BAAALgADCgUJBQAAAA==.',
Ac='Acelord:BAABLgAECn8eAAIBAAkJcRUVLAAWAgABAAkJcRUVLAAWAgAAAA==.Actaeon:BAAALgAECgQJBgAAAA==.',
Ad='Adaar:BAAALgAECgEJAQAAAA==.Adadebox:BAAALgAECgUJCwAAAA==.Adakat:BAAALgADCgEJAQAAAA==.Adanthedark:BAAALgADCgIJAgAAAA==.Adariom:BAAALgADCgUJCAAAAA==.Adrian:BAAALgADCgEJAQAAAA==.Adriannos:BAAALgAECgEJAQAAAA==.',
Ae='Aethir:BAAALgADCgYJBwAAAA==.',
Ag='Agonyy:BAAALgAECgUJEAAAAA==.Agrias:BAAALgAECgEJAgAAAA==.',
Ah='Aharadack:BAAALgADCgUJCwAAAA==.',
Ak='Akawaka:BAAALgAECgEJAQAAAA==.Akiji:BAAALgAECgEJAgAAAA==.Akimurad:BAAALgAECgYJBwAAAA==.',
Al='Alakazam:BAAALgADCgcJBwAAAA==.Alanie:BAAALgADCggJCAABLgAECggJIwACABUeAA==.Ald:BAAALgAECgEJAgAAAA==.Aldebaraum:BAAALgAECgcJDAAAAA==.Alexextreme:BAAALgAECgcJEQAAAA==.Aliaksandr:BAAALgAECgEJAQAAAA==.Alikth:BAAALgADCgYJBgAAAA==.Alista:BAAALgAECgMJAgAAAA==.Allandyr:BAACLgAFFH8IAAIBAAMJ+QsdUgDbAAABAAMJ+QsdUgDbAAAuAAQKfzoAAgEACAklGMk1AO8BAAEACAklGMk1AO8BAAAA.Alvarao:BAAALgAECgQJBAAAAA==.',
Am='Amandadark:BAAALgAECgEJAQAAAA==.Amano:BAAALgADCgYJDAAAAA==.',
An='Anaxthacia:BAAALgADCgMJAwAAAA==.Andarilho:BAAALgAECgEJAQAAAA==.Andinth:BAAALgAECgEJAQAAAA==.Andrepvp:BAAALgADCggJDwAAAA==.Andrit:BAAALgADCgEJAQAAAA==.Anellÿ:BAAALgAECgEJAQAAAA==.Angelloz:BAABLgAECn8oAAIDAAgJyxBteQBgAQADAAgJyxBteQBgAQAAAA==.Anjelvs:BAAALgAECgYJBgAAAA==.Anksunamoon:BAABLgAFFH8FAAICAAUJxAW5KAAGAQACAAUJxAW5KAAGAQAAAA==.Annaoh:BAABLgAECn8cAAIDAAgJVB2wOAAHAgADAAgJVB2wOAAHAgAAAA==.Annia:BAAALgADCgYJBwAAAA==.Anyid:BAAALgAECgMJAwAAAA==.Anãodengoso:BAABLgAECn8pAAMDAAgJSCZgFQDpAgADAAgJSCZgFQDpAgAEAAIJIxKHNwBmAAABLgAECggJKQADAEgmAA==.',
Ap='Apökalÿpsïs:BAABLgAECn8ZAAIFAAcJkxCDgQBaAQAFAAcJkxCDgQBaAQAAAA==.',
Ar='Arator:BAAALgAECggJCgAAAA==.Ardry:BAAALgADCgYJBgAAAA==.Argaloth:BAAALgAECgYJBwAAAA==.Argonzinha:BAAALgAECgEJAQAAAA==.',
As='Ashryel:BAAALgAECgEJAQAAAA==.Ashthon:BAABLgAECn8eAAIBAAcJgxxINgDVAQABAAcJgxxINgDVAQAAAA==.Asmitta:BAAALgADCgQJBAAAAA==.',
At='Atalantha:BAAALgAECgEJAQAAAA==.Atomicdk:BAAALgAECgUJBQAAAA==.Atomictank:BAAALgAECgcJEwAAAA==.Atonos:BAAALgAECgcJCwAAAA==.',
Au='Augustosg:BAAALgAECgYJDAABLgAECgYJDwAGAAAAAA==.Auquenai:BAAALgADCgUJBQAAAA==.Aurielis:BAAALgAECgEJAgAAAA==.',
Av='Averagemage:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAAALgAECgQJBAAAAA==.',
Az='Azadium:BAAALgAECgUJCgAAAA==.Azul:BAAALgAECgQJBwAAAA==.',
Ba='Badayaga:BAAALgADCgIJAgAAAA==.Bakunogrind:BAAALgAECgUJBQABLgAFFAQJBwAHAEMeAA==.Balragouldur:BAAALgAECgQJBgAAAA==.Balthar:BAABLgAECn8gAAQIAAcJOhIAQgAPAQAIAAcJoxEAQgAPAQAJAAQJChFrHQD1AAAHAAQJBg+dmAB2AAAAAA==.Barathrum:BAAALgADCgEJAQAAAA==.Barcaldas:BAAALgAECgUJBgAAAA==.Barrocø:BAAALgAECgQJBQABLgAECggJFAAKAEcYAA==.Basara:BAAALgAECgYJEAAAAA==.Batefraco:BAAALgADCgIJAgAAAA==.',
Bb='Bbiel:BAABLgAECn8hAAMLAAUJwBXBFADqAAALAAUJwBXBFADqAAAMAAEJ3wF9RwEfAAAAAA==.',
Be='Beatriz:BAAALgAECgYJCQAAAA==.Beelgarath:BAAALgAECgUJBwAAAA==.Beherit:BAAALgAECgEJAQAAAA==.Beliall:BAAALgADCgQJBQAAAA==.Belowlight:BAAALgADCgYJEwAAAA==.Belttazar:BAAALgADCgkJDwAAAA==.Bemmaith:BAAALgAECgQJBAAAAA==.Berzan:BAAALgAECgUJCwAAAA==.Beyoond:BAACLgAFFH8ZAAQMAAQJrxVCXgDvAAAMAAMJFBVCXgDvAAANAAEJgBcoGQBTAAALAAEJ+weuIQBIAAAuAAQKfzoABAwACQm+HCwhAFECAAwACQm/GywhAFECAAsABAm3D+cxAPEAAA0AAwnBFrMaAMcAAAAA.',
Bh='Bhalin:BAAALgAECgQJBQAAAA==.',
Bi='Bielinski:BAAALgAECgQJBAAAAA==.Biinarc:BAAALgAECgEJAQAAAA==.',
Bl='Blackdut:BAACLgAFFH8FAAIMAAIJBgIonwBzAAAMAAIJBgIonwBzAAAuAAQKfxUAAwwABwmyER5jAG4BAAwABwl5ER5jAG4BAAsABAkpCoEhAIkAAAAA.Blackrøse:BAAALgADCgYJBgAAAA==.Blackteriaa:BAAALgAECgUJDwAAAA==.Blacrapumzel:BAAALgAECgMJAwAAAA==.Blakwolf:BAAALgAECgEJAQAAAA==.Blankis:BAAALgADCgYJCQAAAA==.Blizther:BAAALgADCgIJAgAAAA==.Bloodh:BAAALgAECgIJBgAAAA==.Bls:BAAALgADCgMJAwAAAA==.',
Bo='Boijf:BAAALgADCgEJAQAAAA==.Boladomal:BAAALgAECgMJBAAAAA==.Bones:BAAALgAECgEJAQAAAA==.Boromy:BAAALgAECgcJDAAAAA==.Boruck:BAAALgAECgIJAwAAAA==.',
Br='Braandom:BAAALgAECgcJEAAAAA==.Bradan:BAABLgAECn8eAAIKAAgJURWcKgAOAgAKAAgJURWcKgAOAgAAAA==.Brandomm:BAAALgAECgYJDgAAAA==.Branmir:BAAALgAECgMJBgAAAA==.Bridda:BAAALgAECgYJDAAAAA==.Brolho:BAAALgADCgEJAQAAAA==.Brusque:BAAALgAECgcJBwAAAA==.Bruzapaladin:BAAALgADCgUJBQAAAA==.',
Bt='Btrcaotics:BAAALgAECgIJCAAAAA==.Btrguard:BAAALgAECgIJAgAAAA==.',
['Bé']='Béto:BAAALgAECggJDgAAAA==.',
['Bí']='Bíbs:BAABLgAECn8VAAIBAAgJkRMjSgCrAQABAAgJkRMjSgCrAQAAAA==.',
Ca='Cabanagé:BAAALgAECgUJBwAAAA==.Cabeludometa:BAAALgAECgEJAwAAAA==.Cabodecobre:BAAALgAECgUJCwAAAA==.Cainmarko:BAAALgAECgYJEAAAAA==.Caiowisk:BAABLgAECn8VAAMMAAgJOQWKjwASAQAMAAgJOQWKjwASAQALAAEJAABPTgAAAAAAAA==.Calir:BAAALgADCgYJFgAAAA==.Calçadora:BAACLgAFFH8FAAIOAAIJYxX9IAClAAAOAAIJYxX9IAClAAAuAAQKf0EAAg4ACQmqIZUEANgCAA4ACQmqIZUEANgCAAAA.Cardrok:BAAALgADCgEJAQAAAA==.Caridosa:BAAALgADCgUJBQAAAA==.Carnius:BAACLgAFFH8HAAMPAAMJmhWyFwDEAAAPAAMJmhWyFwDEAAAQAAEJDAWMOQA0AAAuAAQKf0MABA8ACAlHHgEPAOIBAA8ACAkhHQEPAOIBAAoAAgm6IL6EAEsAABAAAQkPHGlgAEMAAAAA.Casipala:BAAALgAECgIJAgAAAA==.Casuall:BAAALgAECgcJBwAAAA==.Cataclysm:BAAALgAECgMJBAAAAA==.Catalango:BAAALgAECgQJCgAAAA==.Catapó:BAAALgAECgcJDwAAAA==.Catapózão:BAABLgAECn8yAAICAAkJniDlBQBNAwACAAkJniDlBQBNAwAAAA==.Catü:BAAALgAECgEJAQAAAA==.Cavernus:BAAALgADCgMJAwAAAA==.Caves:BAAALgADCgIJAgAAAA==.Caveston:BAAALgADCgUJCgAAAA==.',
Cb='Cbestabr:BAAALgADCgYJBgAAAA==.',
Ch='Chamadmordor:BAAALgAECgMJBQAAAA==.Charats:BAAALgADCgYJDQAAAA==.Charterine:BAAALgADCgYJBgAAAA==.Chaya:BAAALgADCgUJBQAAAA==.Chicknorris:BAAALgADCgUJBQAAAA==.Chifrudaxl:BAAALgAECgMJAwAAAA==.Chrisjks:BAAALgADCgYJCgAAAA==.',
Ci='Cindyn:BAAALgAECgEJAQAAAA==.',
Cl='Clared:BAAALgADCgEJAQAAAA==.Clarkcrente:BAAALgADCgYJBgABLgAECgMJAwAGAAAAAA==.Clebeya:BAAALgADCgQJBAAAAA==.Climps:BAABLgAECn8WAAIBAAgJRRe/MwD3AQABAAgJRRe/MwD3AQAAAA==.',
Co='Cobyx:BAAALgADCgcJDAAAAA==.Cocaferoz:BAAALgADCgEJAQAAAA==.Coffeeaddict:BAAALgADCgMJAwAAAA==.Colugo:BAAALgADCgIJAgAAAA==.Coriisco:BAAALgADCgIJAgAAAA==.Corollaxei:BAABLgAECn83AAQRAAkJsxflCgAcAgARAAkJsxflCgAcAgASAAYJsQn7PQARAQATAAEJWAyJIwAyAAAAAA==.Cosculluela:BAAALgADCgUJBwAAAA==.Cosmuh:BAAALgAECgQJBAAAAA==.',
Cr='Creuzapriest:BAAALgAECgEJAQAAAA==.Crookedyoung:BAAALgAECgEJAwABLgAECgcJEAAGAAAAAA==.Cruzade:BAABLgAECn8UAAMEAAcJXxAUIAD5AAAEAAYJwBAUIAD5AAADAAYJdw+/1gDLAAABLgAFFAIJAwAGAAAAAA==.Cröwllëy:BAACLgAFFH8FAAIUAAMJrgf9lADDAAAUAAMJrgf9lADDAAAuAAQKfyMAAhQACAnZF/k8APoBABQACAnZF/k8APoBAAAA.',
Cu='Cubatao:BAABLgAECn8UAAIBAAYJUxQtdwA4AQABAAYJUxQtdwA4AQAAAA==.Cucaracha:BAAALgAECgUJDwAAAA==.',
Da='Dahhak:BAAALgAECgUJCwAAAA==.Dakhgagul:BAAALgADCgUJBQAAAA==.Dakshayani:BAAALgAECgQJBQAAAA==.Danielbrz:BAAALgAECgUJBwAAAA==.Daniellpvp:BAAALgADCgEJAQAAAA==.Danygatuxa:BAAALgAECgUJDQAAAA==.Daree:BAAALgAECgEJAQAAAA==.Darkenes:BAAALgAECgEJAQAAAA==.Darkinmt:BAAALgADCgcJCAAAAA==.Darknesstk:BAAALgAECgYJDwAAAA==.Darkowllskul:BAAALgAECgQJBgABLgAECgYJEQAGAAAAAA==.Darksiderptc:BAAALgADCgcJDwAAAA==.Darthmansur:BAAALgAFFAEJAQAAAA==.Dasmithy:BAAALgAECgEJAQAAAA==.',
De='Deadvi:BAABLgAECn8UAAIVAAgJHxw2DQA7AgAVAAgJHxw2DQA7AgAAAA==.Deadziin:BAAALgAECgcJEwAAAA==.Deathmäsk:BAAALgADCgcJBwAAAA==.Demetrix:BAAALgADCgkJCgAAAA==.Dennyam:BAAALgAECgYJCQAAAA==.Derothey:BAABLgAECn8pAAIFAAgJYBamUgDMAQAFAAgJYBamUgDMAQAAAA==.Deservis:BAAALgADCgYJBgAAAA==.Deulorem:BAACLgAFFH8NAAIWAAQJZx3sDABVAQAWAAQJZx3sDABVAQAuAAQKfzwAAhYACQmBI48BAJUDABYACQmBI48BAJUDAAAA.Devilblade:BAABLgAECn8RAAIXAAgJXgmljwACAQAXAAgJXgmljwACAQAAAA==.',
Di='Diabolynn:BAAALgAECgcJDgAAAA==.',
Dk='Dkatraia:BAAALgAECgMJAwAAAA==.',
Dn='Dngfafinir:BAAALgAECgkJBwABLgAFFAUJDAADAFgXAA==.Dnghidan:BAACLgAFFH8MAAIDAAUJWBc2MwAtAQADAAUJWBc2MwAtAQAuAAQKfygAAgMACQmrHvohAKICAAMACQmrHvohAKICAAAA.Dngpain:BAAALgAECgUJBAABLgAFFAUJDAADAFgXAA==.Dngtobi:BAAALgAECgUJCQABLgAFFAUJDAADAFgXAA==.',
Do='Dollynhø:BAABLgAECn8eAAIYAAgJsxvEEgAUAgAYAAgJsxvEEgAUAgAAAA==.Donyed:BAAALgAECgQJCAAAAA==.Dottado:BAAALgADCgcJCgAAAA==.',
Dr='Drackah:BAAALgADCgcJBwAAAA==.Draconían:BAAALgAECgEJBwAAAA==.Dracón:BAAALgAECgUJCAAAAA==.Draigo:BAAALgAECgIJAgAAAA==.Dreykar:BAABLgAECn8uAAMXAAkJfBjYHwBCAgAXAAkJfBjYHwBCAgAZAAEJ2BzzJwBOAAAAAA==.Drogorn:BAAALgAECgUJCwAAAA==.Druidaezeki:BAAALgADCgYJCwAAAA==.Druidjm:BAAALgADCgMJAwAAAA==.Druvannar:BAAALgADCgEJAQAAAA==.Dröwränger:BAAALgADCgYJBgAAAA==.',
Du='Dultrasenegl:BAABLgAECn8eAAIBAAYJAA3yZQA2AQABAAYJAA3yZQA2AQAAAA==.Dunois:BAAALgAECgIJBgAAAA==.',
['Dä']='Dähäkä:BAABLgAECn8cAAIDAAgJsRw/LAA3AgADAAgJsRw/LAA3AgAAAA==.',
Ed='Edven:BAACLgAFFH8RAAIRAAMJTANXHwCUAAARAAMJTANXHwCUAAAuAAQKfyEAAhEABgnKDMYlAEgBABEABgnKDMYlAEgBAAAA.',
Ei='Eini:BAAALgAECgEJAQAAAA==.',
El='Elbermt:BAAALgAECgEJAQAAAA==.Elbruxão:BAAALgAECgEJAQAAAA==.Eldrick:BAAALgADCgIJAgAAAA==.Eldros:BAAALgAECgYJCAAAAA==.Elementais:BAAALgAECgcJEwAAAA==.Elgado:BAAALgAECgEJAwAAAA==.Elgatadexota:BAAALgADCgkJCgAAAA==.Eliksir:BAAALgAECgUJBQAAAA==.Ellanor:BAABLgAECn8dAAIFAAgJ+hgXTQDcAQAFAAgJ+hgXTQDcAQAAAA==.Elruth:BAAALgADCggJCAABLgAFFAQJDQAWAGcdAA==.Eltão:BAAALgAECgEJAQAAAA==.Elunah:BAAALgADCgQJBAAAAA==.Elwindor:BAAALgAECgEJAQAAAA==.Elyind:BAAALgADCgYJBwAAAA==.Elyn:BAAALgAECgQJBAAAAA==.',
Em='Emmymm:BAAALgAECgEJAQAAAA==.',
En='Endeavour:BAAALgADCgEJAQAAAA==.Enegadiel:BAABLgAECn8fAAIDAAcJNxEniwA/AQADAAcJNxEniwA/AQAAAA==.Enoia:BAAALgADCgcJDQAAAA==.',
Eq='Equidnah:BAAALgAECgIJAgAAAA==.',
Er='Erickya:BAAALgAECggJEgAAAA==.Ervadocè:BAABLgAECn8ZAAIaAAYJwhhlMABBAQAaAAYJwhhlMABBAQAAAA==.Ervelino:BAAALgAECgMJBAAAAA==.',
Es='Estrogosbald:BAABLgAECn8ZAAIbAAgJMQzWBQBXAQAbAAgJMQzWBQBXAQAAAA==.',
Eu='Euteinvoco:BAAALgAECgIJAgAAAA==.',
Ev='Evely:BAABLgAECn8aAAIcAAcJgxgXDQB5AQAcAAcJgxgXDQB5AQAAAA==.',
Ex='Exarch:BAACLgAFFH8NAAIOAAQJaRTRDwA/AQAOAAQJaRTRDwA/AQAuAAQKfysAAg4ACQm/Ib4CAAwDAA4ACQm/Ib4CAAwDAAAA.',
Fa='Faengar:BAAALgAECgUJCAAAAA==.Falcondk:BAAALgAECgEJAQAAAA==.Falconess:BAAALgADCgEJAQAAAA==.',
Fe='Feathria:BAAALgAECgMJAwAAAA==.Felipebritoo:BAAALgAECgMJBgABLgAECgYJEQAGAAAAAA==.Fenrirsp:BAAALgAFFAIJBAAAAA==.Ferdruiid:BAAALgADCgkJEwAAAA==.Feropudo:BAAALgADCgkJDgAAAA==.Ferrarig:BAAALgAECgEJBQAAAA==.',
Fi='Figy:BAAALgAECgQJBAAAAA==.',
Fl='Flemma:BAABLgAECn8YAAIRAAgJJgcuGwAVAQARAAgJJgcuGwAVAQAAAA==.Flexer:BAAALgAECgIJAgAAAA==.Flores:BAAALgADCgMJBQAAAA==.Floridastyle:BAABLgAECn8fAAIdAAUJTxZ3MQAxAQAdAAUJTxZ3MQAxAQAAAA==.',
Fo='Foguerosa:BAACLgAFFH8JAAMFAAMJpRyQLwD4AAAFAAMJpRyQLwD4AAAeAAEJggCMBQAyAAAuAAQKfxYAAgUACAlpIVREAGsCAAUACAlpIVREAGsCAAAA.Folghunthir:BAAALgADCgQJBAAAAA==.',
Fr='Frankkquini:BAAALgADCgYJEgAAAA==.Friodokrl:BAACLgAFFH8FAAIUAAMJIw4+iQDVAAAUAAMJIw4+iQDVAAAuAAQKfzYAAxUACQkHHrMMACYCABUACQkuG7MMACYCABQACAkdGoU9APkBAAAA.Fritzgerhart:BAAALgAECgEJAQAAAA==.Frostkller:BAAALgADCgIJAgAAAA==.Frostmhaw:BAAALgADCgUJBQAAAA==.Frostreaper:BAAALgAECgQJBgAAAA==.',
Fu='Fubukiofhell:BAABLgAECn8ZAAIFAAcJsBpQUwDKAQAFAAcJsBpQUwDKAQAAAA==.Fuginzao:BAAALgAECgEJAQAAAA==.Furtacor:BAAALgADCgcJBwAAAA==.Furyarh:BAAALgAECgMJAwAAAA==.',
['Fí']='Fí:BAAALgADCggJDgABLgAECgkJHQABALAaAA==.',
Ga='Gabana:BAAALgADCgQJBAAAAA==.Gabdobbuh:BAAALgAECgUJCAAAAA==.Gabn:BAAALgAECgIJAwAAAA==.Gafgar:BAAALgADCgUJCQAAAA==.Gaila:BAAALgAECgIJBgAAAA==.Galduin:BAABLgAECn8tAAIKAAkJQRhXFQAxAgAKAAkJQRhXFQAxAgAAAA==.',
Ge='Gedexx:BAAALgAECgMJAgAAAA==.Geduntruppa:BAAALgAECgYJBgAAAA==.Gentioiroh:BAAALgAECgMJAwAAAA==.',
Gh='Ghorderp:BAAALgADCgcJDAAAAA==.Ghosstt:BAAALgAECgEJAgAAAA==.Ghoulrozon:BAAALgADCgYJBgAAAA==.',
Gi='Giovannapala:BAABLgAECn8XAAIDAAgJ/A1/jAA9AQADAAgJ/A1/jAA9AQAAAA==.Giovannasham:BAAALgAECgEJAgAAAA==.Giripoca:BAAALgAECgQJCQAAAA==.',
Gl='Gladsmonge:BAABLgAECn8mAAIfAAcJ3h+EEgBpAgAfAAcJ3h+EEgBpAgAAAA==.Glorcckk:BAAALgAECgMJAwAAAA==.',
Gn='Gnomagga:BAAALgAECgcJEAABLgAECggJNgAEAB8cAA==.Gnomohabe:BAAALgADCgQJBgAAAA==.',
Go='Goddofwarr:BAAALgADCggJEQAAAA==.Gonb:BAAALgADCgUJBQAAAA==.Goueki:BAABLgAECn80AAMBAAgJmBriKAAkAgABAAgJmBriKAAkAgAcAAIJSwEtgwA8AAAAAA==.',
Gr='Greenzle:BAAALgAECgUJBgAAAA==.Grillnborst:BAAALgADCgEJAgAAAA==.Grilonp:BAAALgADCgQJCAAAAA==.Grogath:BAAALgAECgQJCAAAAA==.Grogtixa:BAAALgAECggJCQABLgAECgkJKgAIAFcWAA==.Gromoff:BAABLgAFFH8HAAIMAAIJwiQFcwDEAAAMAAIJwiQFcwDEAAAAAA==.Grunmonk:BAAALgADCgEJAQAAAA==.Grømmar:BAAALgADCgMJAwAAAA==.',
Gu='Gudangara:BAAALgADCgYJBgAAAA==.Gumy:BAAALgAECgEJAwAAAA==.Guztaverdead:BAAALgADCgQJBAAAAA==.',
['Gü']='Güistrong:BAAALgADCgIJAwAAAA==.',
Ha='Haakaí:BAAALgAECgUJEAAAAA==.Haandir:BAAALgAECgIJAwAAAA==.Hackterin:BAAALgADCgYJBgAAAA==.Hadorah:BAAALgAECgUJBgAAAA==.Haerys:BAAALgADCgYJBgAAAA==.Handhemirr:BAAALgAECgMJBAAAAA==.Harany:BAABLgAECn8fAAMdAAgJlw/WJwBuAQAdAAgJlw/WJwBuAQAgAAYJygsxQgDhAAAAAA==.Harrypotinho:BAABLgAECn8uAAIMAAgJ4xcQOQDpAQAMAAgJ4xcQOQDpAQAAAA==.Haunexd:BAAALgADCgMJAwAAAA==.Havenna:BAAALgAECgUJCAAAAA==.',
He='Headøhunter:BAAALgAECgEJAgAAAA==.Healgate:BAAALgAECgEJAQAAAA==.Heeythaly:BAAALgADCgcJDwAAAA==.Helessa:BAAALgAECgEJAQAAAA==.Hellenah:BAAALgADCggJCAAAAA==.Herablack:BAAALgAECgMJAgAAAA==.Herika:BAAALgADCgMJAwAAAA==.',
Hi='Hidenz:BAAALgADCgIJAgAAAA==.',
Ho='Hoem:BAAALgAECgMJAwAAAA==.Holand:BAAALgAECgYJDAAAAA==.Holydread:BAAALgAECgIJAgAAAA==.',
Hu='Hulig:BAABLgAECn8nAAMDAAgJcR90IwBfAgADAAgJcR90IwBfAgAEAAEJAQd3TAAnAAABLgAFFAEJAQAGAAAAAA==.Hunthearthas:BAAALgAECgMJAwAAAA==.',
['Hø']='Høkulani:BAABLgAECn8cAAIFAAcJchELfwBfAQAFAAcJchELfwBfAQAAAA==.',
Ib='Ibrad:BAAALgAECgQJBAAAAA==.Ibuprofens:BAAALgAECgEJAQAAAA==.',
Ic='Iceyag:BAAALgAECgIJAgAAAA==.',
Ik='Ikiam:BAAALgAECgQJCAAAAA==.Ikslawok:BAAALgADCgYJEAAAAA==.',
Il='Ileria:BAAALgAECgYJBwAAAA==.Iliriana:BAAALgADCgQJBwAAAA==.Illarion:BAAALgADCgQJBAAAAA==.Illidanos:BAABLgAECn8cAAIhAAgJ/RGfGwB/AQAhAAgJ/RGfGwB/AQAAAA==.Illidansan:BAAALgAECgQJBQABLgAECgYJCwAGAAAAAA==.Illidris:BAAALgAECgUJBQAAAA==.Illumiinated:BAAALgAECgYJEgAAAA==.',
In='Incarus:BAAALgAECgcJCgAAAA==.Incognita:BAAALgAECgEJAQAAAA==.Indis:BAAALgADCgQJBgAAAA==.Interst:BAAALgAECgEJAQAAAA==.',
Ir='Irion:BAAALgAECgQJBQAAAA==.',
Is='Iscalio:BAAALgAECgYJCgAAAA==.',
It='Itatchii:BAAALgADCgkJCQAAAA==.',
Iv='Ivinhosilva:BAAALgADCgYJBgAAAA==.',
Ja='Jackdawnsong:BAAALgAECgcJDAAAAA==.Jaene:BAAALgADCgYJCQAAAA==.Jahuun:BAABLgAECn8ZAAIDAAcJ4wvxnQAfAQADAAcJ4wvxnQAfAQAAAA==.Jamantoso:BAAALgAECgEJAQAAAA==.',
Je='Jeess:BAAALgADCgMJAwAAAA==.Jefflich:BAABLgAECn8iAAMUAAgJ4AqUiQBuAQAUAAgJiwmUiQBuAQAiAAEJhxJtMQAvAAAAAA==.',
Jg='Jg:BAAALgAECgUJBwABLgAECgYJDgAGAAAAAA==.',
Ji='Jinknu:BAAALgAECgIJBAAAAA==.',
Jo='Jottapeg:BAAALgADCgcJAwAAAA==.',
Ju='Jubard:BAAALgADCgkJDAAAAA==.Juliamarques:BAAALgAECgMJBAAAAA==.',
['Jü']='Jüllÿe:BAAALgADCgEJAQAAAA==.',
Ka='Kaaellthas:BAAALgAECgQJCgAAAA==.Kacolux:BAAALgADCgEJAQAAAA==.Kaisaargente:BAAALgAECgEJAQAAAA==.Kakarotho:BAAALgAECgMJCQAAAA==.Kalarath:BAAALgAECgYJBgAAAA==.Kaldonios:BAAALgADCgcJEgAAAA==.Kalma:BAAALgAECgEJAQAAAA==.Kamasutram:BAAALgADCgYJCwAAAA==.Kanadriel:BAAALgAECgcJDAAAAA==.Kanarinho:BAABLgAECn8wAAICAAkJIh/iBwArAwACAAkJIh/iBwArAwAAAA==.Karmussie:BAAALgADCgEJAQAAAA==.Karmysh:BAAALgAECgMJAwAAAA==.Katari:BAAALgAECgYJCgABLgAECgkJEQAGAAAAAA==.Kayanz:BAAALgADCgUJBQAAAA==.Kazandra:BAAALgADCgYJBgAAAA==.',
Ke='Kendars:BAABLgAECn8VAAQaAAYJ0xKfSAAKAQAaAAUJJhKfSAAKAQACAAUJFQ+5dgDzAAAjAAEJhRVyPgBDAAABLgAFFAMJBwAVALAMAA==.Ket:BAAALgADCgMJAwAAAA==.',
Kh='Khanmir:BAAALgAECgMJBgAAAA==.Kharon:BAAALgAECgYJBgAAAA==.Khild:BAAALgAECgYJDQAAAA==.Khonar:BAAALgADCgUJBwAAAA==.',
Ki='Killerdek:BAAALgAECgUJBQAAAA==.Killshoty:BAAALgAECgEJAgAAAA==.',
Kk='Kkiara:BAAALgAECgMJBAAAAA==.',
Kl='Klissera:BAAALgADCgQJBAAAAA==.Kluzlocak:BAABLgAECn8iAAIdAAYJUQyrOAAIAQAdAAYJUQyrOAAIAQAAAA==.',
Kn='Knnabys:BAAALgAECgEJAQAAAA==.',
Ko='Komah:BAAALgAECgEJAQAAAA==.Korav:BAAALgAECgMJCQAAAA==.Korium:BAAALgADCgUJBQABLgAECgkJNgAPAB4kAA==.Koruno:BAAALgADCgYJBgAAAA==.',
Kr='Krosn:BAAALgAECgEJAQAAAA==.Krozhul:BAAALgAECgQJBwAAAA==.Krypthor:BAAALgAECgEJAQAAAA==.',
Ku='Kurnous:BAAALgAECgEJAQAAAA==.Kutirenzo:BAAALgADCgUJBwAAAA==.',
La='Lafiel:BAAALgAECgcJEQAAAA==.Lagertha:BAAALgADCgYJBgAAAA==.Lahnara:BAAALgAECgEJAQAAAA==.Lambayoda:BAAALgAECgYJBwAAAA==.Lamelo:BAAALgADCgYJBgAAAA==.Lanmo:BAAALgAECgcJAgAAAA==.Largatixazul:BAAALgADCgUJBgAAAA==.Lataria:BAAALgADCgEJAQAAAA==.Laurea:BAAALgAECgkJEQAAAA==.',
Le='Leebron:BAAALgAECgYJDAAAAA==.Lefthalas:BAAALgAECgUJCgAAAA==.Leitchero:BAAALgAECgIJAgAAAA==.Lemaz:BAAALgAECgEJAQAAAA==.Lemonhunter:BAAALgAECgYJCAAAAA==.Leonelmessi:BAAALgAFFAQJAQAAAA==.Lesco:BAAALgADCgMJAwAAAA==.',
Li='Lianele:BAAALgAECgYJCgAAAA==.Liaras:BAABLgAECn8pAAMWAAgJXBcPGwDYAQAWAAgJXBcPGwDYAQAgAAIJzABFaQAmAAAAAA==.Libertinagem:BAAALgAECgYJDQAAAA==.Lichtbaum:BAABLgAECn8ZAAMCAAgJyxxaIABAAgACAAgJyxxaIABAAgAaAAQJrhY/SQDKAAAAAA==.Lightsertrop:BAAALgADCgIJAgAAAA==.Liifecomm:BAACLgAFFH8SAAIWAAUJSRQUCwBwAQAWAAUJSRQUCwBwAQAuAAQKfzkAAhYACQkBHpkKAKgCABYACQkBHpkKAKgCAAAA.Liike:BAAALgAECgcJCwAAAA==.Linestra:BAAALgADCgUJBQAAAA==.Liniak:BAAALgAECgcJEAAAAA==.Lisong:BAAALgADCgUJCQAAAA==.Littlepurple:BAACLgAFFH8JAAIXAAMJzxJ7GwD2AAAXAAMJzxJ7GwD2AAAuAAQKfyQAAhcACQl0HJwYAMICABcACQl0HJwYAMICAAAA.',
Lo='Longhai:BAAALgADCgUJCAAAAA==.Lookatmylock:BAABLgAECn8iAAMLAAYJ/xu5CgB5AQALAAYJ/xu5CgB5AQAMAAIJmBEdCAFMAAAAAA==.Lordpain:BAAALgAECgcJDQAAAA==.Lortherti:BAAALgAECgIJAgAAAA==.Lorwin:BAABLgAECn8UAAIBAAgJhBmBPQDTAQABAAgJhBmBPQDTAQAAAA==.Lotusbr:BAAALgADCgEJAQAAAA==.Louisenacioo:BAABLgAECn8UAAMRAAcJUhDVEwB5AQARAAcJUhDVEwB5AQASAAMJqwUfdQBUAAAAAA==.Loátrak:BAAALgADCgMJAwAAAA==.',
Lu='Luanne:BAAALgADCgEJAQAAAA==.Luccablack:BAAALgAECgMJAwAAAA==.Luccagelido:BAAALgAECgEJAQAAAA==.Lucyx:BAAALgAECgIJAgAAAA==.Luidar:BAAALgAECgQJBAAAAA==.Lukaslions:BAABLgAECn8dAAIKAAkJaA8FJwCtAQAKAAkJaA8FJwCtAQAAAA==.Lunarie:BAAALgAECgYJEwABLgAECgcJBwAGAAAAAA==.Luphoe:BAABLgAECn8nAAMCAAcJ9RzHJwAWAgACAAcJ9RzHJwAWAgAaAAQJkw6bWgCMAAAAAA==.Luxanä:BAAALgAECgYJBgAAAA==.',
['Lé']='Léio:BAAALgADCgcJCAAAAA==.Léora:BAAALgADCgIJAgAAAA==.',
['Lø']='Lørdsith:BAAALgAECgYJCAABLgAECggJBgAGAAAAAA==.',
['Lÿ']='Lÿcäns:BAAALgADCgMJAwAAAA==.',
Ma='Madagalux:BAABLgAECn8pAAINAAgJNwpLDQBjAQANAAgJNwpLDQBjAQAAAA==.Madalenna:BAAALgAECgMJBQAAAA==.Madjack:BAAALgAECgMJAwAAAA==.Madushi:BAAALgAFFAEJAQAAAA==.Madzerø:BAAALgAECgEJAQAAAA==.Magatiun:BAAALgADCgMJBAAAAA==.Magogunt:BAABLgAECn8hAAIFAAkJMxGWSwDhAQAFAAkJMxGWSwDhAQAAAA==.Maguul:BAABLgAECn8YAAIEAAgJ5hVsDwCxAQAEAAgJ5hVsDwCxAQAAAA==.Magzifeh:BAABLgAECn8UAAIBAAcJ3SCKMgD7AQABAAcJ3SCKMgD7AQAAAA==.Mahadevi:BAAALgADCgIJAgAAAA==.Mahdemon:BAAALgAECgUJBQAAAA==.Maiconhood:BAAALgAFFAEJAQAAAA==.Malandrvs:BAAALgAFFAEJAwAAAA==.Maljamim:BAAALgADCgIJAgAAAA==.Mamuthwar:BAABLgAECn8ZAAMKAAcJnRgeNgDQAQAKAAcJnRgeNgDQAQAQAAEJMQ7ZQQA1AAAAAA==.Mandingavudu:BAAALgAECgYJBwABLgAECggJEwAGAAAAAA==.Manei:BAAALgAECgMJAwAAAA==.Mangalarga:BAAALgADCgEJAQAAAA==.Manmoden:BAAALgADCgUJBQABLgAECggJEwAGAAAAAA==.Mannatur:BAAALgAECggJEwAAAA==.Manopaladino:BAAALgADCgYJBgAAAA==.Manowlo:BAAALgAECgMJAwAAAA==.Manzagon:BAAALgAECgUJCAABLgAECggJEwAGAAAAAA==.Marmelo:BAAALgADCgQJBAAAAA==.Marretasanta:BAABLgAECn8kAAIDAAcJCRQbfgBYAQADAAcJCRQbfgBYAQAAAA==.Marù:BAAALgAECgYJCwAAAA==.Marúh:BAACLgAFFH8SAAIHAAUJPRjQGABzAQAHAAUJPRjQGABzAQAuAAQKfycAAgcACAnzIsQFABYDAAcACAnzIsQFABYDAAAA.Matedellmor:BAAALgADCgIJAwAAAA==.Matroná:BAAALgADCggJBwAAAA==.Maxmorf:BAAALgADCgUJBQAAAA==.Mayarabr:BAAALgAECgYJDQAAAA==.Mazeratos:BAAALgAECgMJBQAAAA==.',
Mc='Mcorelhao:BAAALgADCgEJAQAAAA==.',
Me='Medoza:BAAALgAECgQJBgAAAA==.Megrezz:BAAALgAECgEJAQAAAA==.Mehiel:BAAALgAECgEJAQAAAA==.Mekihlvshtak:BAAALgAECgYJBwAAAA==.Meliøðas:BAAALgADCgEJAQAAAA==.Mendingu:BAABLgAECn8UAAIKAAgJRxgYKAAdAgAKAAgJRxgYKAAdAgAAAA==.Mercenarybr:BAAALgAECgEJAgAAAA==.Merumim:BAAALgAECgYJCwAAAA==.Metalgirl:BAAALgADCgYJCwAAAA==.Methamorfo:BAAALgADCggJCQAAAA==.',
Mi='Midrão:BAAALgAECggJEwAAAA==.Miisuky:BAAALgADCgUJBAAAAA==.Mikasaackerr:BAAALgAECgEJAgAAAA==.Milczarek:BAAALgAECgEJAwAAAA==.Mindlocker:BAABLgAECn8cAAIMAAcJxgiMigAbAQAMAAcJxgiMigAbAQAAAA==.Minorus:BAAALgAECgcJEgAAAA==.Mistifs:BAABLgAECn8gAAIfAAgJMx2mDgCUAgAfAAgJMx2mDgCUAgAAAA==.Miticamais:BAAALgADCgMJAwAAAA==.',
Mo='Modogz:BAAALgADCgYJBgAAAA==.Momongadk:BAAALgADCgcJBwAAAA==.Monkeydking:BAAALgADCgUJBQAAAA==.Morania:BAABLgAECn8XAAILAAgJUwa6FADqAAALAAgJUwa6FADqAAAAAA==.Mordekais:BAAALgAECgIJAgAAAA==.Morganne:BAAALgAECgEJAQAAAA==.Morinami:BAAALgADCgUJBwAAAA==.Moriyama:BAABLgAECn8mAAMCAAgJshx9JwABAgACAAcJuBt9JwABAgAaAAIJaAsjawBZAAAAAA==.Morphisz:BAAALgAECgcJCwABLgAECggJEwAGAAAAAA==.Morphiszs:BAAALgAECgMJBQABLgAECggJEwAGAAAAAA==.Morphizs:BAAALgAECgEJAgABLgAECggJEwAGAAAAAA==.Mortesan:BAAALgAECgEJAQABLgAECgYJCwAGAAAAAA==.',
Mp='Mpastor:BAAALgADCgUJBQAAAA==.',
Mu='Muca:BAAALgADCgEJAQAAAA==.Muho:BAAALgADCgEJAQAAAA==.Mukonha:BAABLgAECn8jAAIMAAcJeA4/fwAwAQAMAAcJeA4/fwAwAQAAAA==.',
['Mã']='Mãoleves:BAAALgADCgEJAQAAAA==.',
['Må']='Måximus:BAAALgAECgMJBQAAAA==.',
['Mü']='Müller:BAAALgADCgEJAQABLgAECgcJEAAGAAAAAA==.',
Na='Naeryndam:BAAALgADCgEJAQAAAA==.Namyara:BAAALgAECgEJAQAAAA==.Narutowow:BAAALgADCgMJAwAAAA==.Natcmd:BAAALgADCggJFAAAAA==.Navira:BAAALgAECgEJAQAAAA==.Nayanna:BAAALgADCgcJDQAAAA==.',
Ne='Negblack:BAAALgAFFAIJAwAAAA==.Neggi:BAAALgAECgUJBwAAAA==.Nemesysy:BAAALgAECgMJAwAAAA==.Nerphien:BAAALgADCgUJBQAAAA==.Nesktpally:BAAALgAECgcJCAAAAA==.Netbrood:BAAALgADCgUJBgABLgAECgUJBwAGAAAAAA==.Netbrother:BAAALgAECgUJBwAAAA==.Nethdorai:BAAALgADCgQJBAAAAA==.Netherbane:BAABLgAECn8gAAMQAAcJjhrgDwDYAQAQAAcJjhrgDwDYAQAKAAIJGQ9BkgA0AAAAAA==.Nezuko:BAAALgADCgcJEQABLgAECggJLgAMAOMXAA==.',
Ni='Nightmære:BAAALgAECgQJCwAAAA==.Nikelok:BAABLgAECn8VAAIMAAcJRgYVnQD6AAAMAAcJRgYVnQD6AAAAAA==.Ninfador:BAABLgAECn8eAAIdAAYJgxdRKwBXAQAdAAYJgxdRKwBXAQAAAA==.Ninpus:BAAALgAECgMJAwAAAA==.',
No='Noobmasteer:BAAALgADCgIJAgAAAA==.Nooneknow:BAACLgAFFH8FAAIUAAMJghPphADaAAAUAAMJghPphADaAAAuAAQKfzgAAhQACQlUISkSAMsCABQACQlUISkSAMsCAAAA.Nosios:BAAALgAECgYJBgAAAA==.Nosrede:BAAALgAECgEJAQAAAA==.Notz:BAAALgADCgMJBAAAAA==.',
Nu='Nucciwarrior:BAAALgAECgUJCAAAAA==.Nuccixama:BAAALgAECgcJCQAAAA==.Nuriel:BAAALgAECgYJBQAAAA==.',
Ny='Nyde:BAAALgAECgMJAwAAAA==.',
['Nø']='Nøar:BAAALgADCgIJAgAAAA==.',
Oa='Oakshlar:BAAALgAFFAEJAQAAAA==.',
Oc='Ocelaris:BAAALgAECgEJAgAAAA==.',
Oh='Ohlu:BAAALgAECgYJCQAAAA==.Ohluh:BAAALgAECgcJDQAAAA==.',
Or='Oryana:BAAALgAECgEJAQAAAA==.Oríon:BAAALgADCgIJAgAAAA==.',
Ot='Otton:BAABLgAECn8kAAIDAAcJmgltuwDxAAADAAcJmgltuwDxAAAAAA==.',
Ov='Overnigth:BAAALgADCgIJAgAAAA==.Overwalker:BAAALgAECgEJAgAAAA==.Ovosemdente:BAAALgADCgEJAQAAAA==.',
Ow='Owllskull:BAAALgAECgYJEQAAAA==.',
Oz='Ozovo:BAAALgAECgcJDwAAAA==.',
Pa='Pacoka:BAAALgADCgQJBQAAAA==.Padrafferty:BAAALgADCgcJBwAAAA==.Paidesanto:BAAALgAECgYJEAAAAA==.Paidesantox:BAABLgAECn8VAAIaAAcJCgmAPgD5AAAaAAcJCgmAPgD5AAABLgAECgkJLQAKAEEYAA==.Paidocharles:BAAALgAECgEJAgAAAA==.Paladinokun:BAAALgAECgYJCwAAAA==.Palanis:BAAALgAECgcJBwAAAA==.Palazarta:BAAALgAECgcJEQAAAA==.Pandavoli:BAAALgAECgUJDAAAAA==.Pangolinho:BAAALgAECgMJAwAAAA==.Panky:BAAALgAECgQJBAAAAA==.Panquecudo:BAAALgADCgIJAgAAAA==.',
Pd='Pdois:BAAALgADCgMJAwAAAA==.',
Pe='Pesscador:BAAALgAECgMJAwAAAA==.Petrolesk:BAAALgAECgYJCgAAAA==.',
Pi='Piriguetee:BAAALgADCgEJAQAAAA==.Pirro:BAAALgAECgEJAQAAAA==.Pisadinha:BAAALgADCgcJBwAAAA==.',
Pk='Pkzimn:BAAALgADCgUJBQAAAA==.',
Pl='Playsson:BAAALgAECgYJEgAAAA==.Plottwist:BAAALgADCgcJDwABLgAECgkJMAAUAOkYAA==.',
Po='Pogonus:BAAALgADCgIJAgAAAA==.Pontocego:BAAALgAECgQJBAAAAA==.Pororocaa:BAAALgAECgMJAwAAAA==.Posturado:BAAALgADCgEJAQAAAA==.Powerworth:BAAALgAECgEJAQAAAA==.',
Pr='Pravios:BAAALgAECgMJBgAAAA==.Priestkill:BAAALgADCgcJCQAAAA==.Primewolf:BAAALgAECgMJAwAAAA==.',
Ps='Psicomanic:BAAALgADCgMJAwAAAA==.',
Pt='Pterodactilo:BAAALgAECgYJAQAAAA==.',
Pu='Puherito:BAAALgAECgUJCwAAAA==.Purgas:BAAALgAFFAEJAQAAAA==.',
Qu='Quinthalam:BAAALgADCgMJAwAAAA==.',
Ra='Rafac:BAAALgAECgEJAgABLgAECggJEAAGAAAAAA==.Rafazinho:BAAALgADCgQJBAAAAA==.Ramyna:BAAALgAECgMJBQAAAA==.Ramyra:BAAALgADCgcJDQAAAA==.Raphaeldh:BAAALgAECgEJAgAAAA==.Raphahunterr:BAAALgADCgEJAQAAAA==.Raposa:BAAALgADCgEJAQAAAA==.Raposinha:BAAALgADCgMJAwAAAA==.Rarkway:BAAALgAECgcJCwAAAA==.Ravenblak:BAAALgADCgMJAwAAAA==.Rayanne:BAAALgADCgYJBgAAAA==.',
Re='Reckfull:BAAALgAECgYJBgAAAA==.Regininha:BAAALgAECgEJAQAAAA==.Reloumifrend:BAAALgAECgcJCgAAAA==.Rendros:BAAALgADCgUJBQAAAA==.',
Rh='Rhaegaar:BAAALgAECgcJDQAAAA==.Rhanideri:BAAALgADCgEJAQAAAA==.Rhodinius:BAAALgAECgMJCAAAAA==.',
Ri='Rivotreel:BAAALgADCgQJBAAAAA==.',
Ro='Robeerth:BAAALgAFFAIJAwAAAA==.Rochera:BAAALgAECgEJAQAAAA==.Rokhanar:BAAALgAECgUJCwAAAA==.',
Ru='Rudemonster:BAAALgAECgEJAQAAAA==.Ruhtarr:BAAALgADCgEJAQAAAA==.',
Ry='Ryukato:BAAALgAECgQJBQAAAA==.',
Sa='Saek:BAAALgAECgcJEgAAAA==.Saelor:BAAALgAECgEJAgAAAA==.Sanderclone:BAAALgAECgEJAQAAAA==.Sanguenafaca:BAAALgADCgYJCgAAAA==.Santiss:BAABLgAECn8WAAIDAAYJDhWKlgAsAQADAAYJDhWKlgAsAQAAAA==.Santorini:BAAALgAECgcJDQAAAA==.Saphirot:BAAALgADCgUJBQAAAA==.Saphis:BAAALgADCgEJAQAAAA==.Sardado:BAAALgAECgEJAQAAAA==.Sardron:BAAALgADCgMJAwAAAA==.',
Sc='Scanorr:BAAALgAECgYJDAAAAA==.Scheffers:BAAALgAECgYJEAAAAA==.',
Se='Selah:BAAALgADCgMJBQAAAA==.Selver:BAAALgAECgcJCAABLgAFFAcJGgAgALAaAA==.Selüne:BAAALgAECgcJDQAAAA==.Sephora:BAAALgAECgYJCwABLgAECggJKQAWAFwXAA==.Sevagoth:BAAALgAECgEJAQAAAA==.',
Sh='Shadowlock:BAAALgADCgIJAQABLgAECgYJDgAGAAAAAA==.Shadowmornac:BAAALgAECgMJBAAAAA==.Shamanica:BAAALgAECgEJAgAAAA==.Shamateus:BAAALgADCggJEwAAAA==.Shasuna:BAAALgADCgIJAgAAAA==.Shaunnun:BAAALgADCgEJAQAAAA==.Shenloong:BAAALgADCgYJBgAAAA==.Shinnók:BAAALgAECgIJAgAAAA==.Shiíro:BAAALgAFFAIJBAABLgAFFAUJEwADABAkAA==.Shynato:BAAALgADCgEJAQAAAA==.Shynock:BAAALgADCgEJAQAAAA==.Shyriull:BAAALgADCggJDgAAAA==.Shyzuno:BAAALgADCgQJBAAAAA==.Shãka:BAAALgADCgMJAwAAAA==.',
Si='Siladriel:BAAALgADCgMJAwAAAA==.Sirgonzo:BAABLgAECn8XAAIDAAkJtxcrNgAQAgADAAkJtxcrNgAQAgAAAA==.',
Sk='Skullexus:BAAALgAECgMJBAAAAA==.Skunkbr:BAAALgADCgEJAQAAAA==.',
Sl='Sleepychety:BAAALgAECgUJBgAAAA==.Slowsmoke:BAAALgADCgYJBwAAAA==.Slyfer:BAAALgAFFAIJAgAAAA==.',
Sn='Snatzz:BAAALgADCgMJAgAAAA==.',
So='Soggoth:BAAALgADCgkJCQAAAA==.Solk:BAAALgAECgMJBQAAAA==.Sontarfury:BAAALgAECgEJAQAAAA==.Sorim:BAABLgAECn8jAAICAAYJYB/jJwD/AQACAAYJYB/jJwD/AQAAAA==.Soryan:BAABLgAECn8iAAICAAcJ4RSCOQCdAQACAAcJ4RSCOQCdAQAAAA==.Soulassassin:BAAALgADCgIJAwAAAA==.Soulhell:BAABLgAECn8cAAIdAAYJaxQ5LgBEAQAdAAYJaxQ5LgBEAQAAAA==.',
Sp='Spartanlofs:BAAALgADCgcJEQAAAA==.Spawndeath:BAAALgADCgEJAQAAAA==.',
Ss='Ssushii:BAAALgAECgEJAQAAAA==.',
St='Staffkiller:BAAALgAECgIJAgAAAA==.Stigmata:BAAALgAECgEJAQAAAA==.Stixlightmix:BAABLgAFFH8FAAMYAAMJ5hH6JQCVAAAYAAIJORj6JQCVAAAkAAEJQAWSVQA1AAAAAA==.Stixmixdk:BAABLgAFFH8FAAIVAAMJIhZDKAB9AAAVAAMJIhZDKAB9AAAAAA==.Stixmixwarr:BAAALgAFFAYJAQAAAA==.Straz:BAAALgADCgQJBAAAAA==.Strongman:BAAALgAECgYJBgAAAA==.Stx:BAAALgAECgUJCQAAAA==.',
Su='Subsdk:BAACLgAFFH8UAAIUAAUJHBGgWgAlAQAUAAUJHBGgWgAlAQAuAAQKfyQAAxQACAmUHYc/APIBABQACAmUHYc/APIBACIAAQnfHzYnAF4AAAAA.Sunwalkers:BAAALgAECgUJBgAAAA==.Supfurry:BAAALgAECgMJAwAAAA==.',
Sw='Swam:BAAALgADCgkJCQAAAA==.Sweetl:BAAALgAECgQJBAAAAA==.',
Sy='Systeni:BAAALgADCgkJCwAAAA==.',
['Sø']='Søøssø:BAAALgAECgYJCAAAAA==.',
Ta='Taha:BAAALgAECgYJDgAAAA==.Taillys:BAAALgADCgMJBAAAAA==.Tainy:BAAALgAECgEJAQAAAA==.Takemywand:BAAALgADCgUJBQABLgAECgcJFAARAFIQAA==.Takenaka:BAAALgADCgMJAwAAAA==.Tarez:BAAALgAECgkJDgAAAA==.Tarfonir:BAAALgAECgYJCQAAAA==.Tavalira:BAAALgADCgYJBgAAAA==.',
Te='Tealen:BAAALgAECgEJAQAAAA==.Ted:BAAALgAECgcJDAAAAA==.Teiseken:BAAALgAECgcJBwAAAA==.Tempesfúria:BAAALgADCgIJAgAAAA==.Tenébria:BAAALgAECgcJBwAAAA==.Teratsemknk:BAAALgAECgUJBQAAAA==.',
Th='Tharnforge:BAAALgAECgEJAQAAAA==.Thejokker:BAACLgAFFH8GAAIKAAMJgQDKQABnAAAKAAMJgQDKQABnAAAuAAQKfxcAAgoABwl6BC5eAMEAAAoABwl6BC5eAMEAAAAA.Thelaststorm:BAAALgAECgkJAwAAAA==.Themooster:BAAALgAFFAIJAwAAAA==.Thepickles:BAAALgADCgkJIAAAAA==.Thepunk:BAAALgAECgQJEQAAAA==.Thesindorei:BAAALgAECgEJAgAAAA==.Thintor:BAAALgADCgEJAQAAAA==.Thormento:BAABLgAECn8VAAIHAAcJkBGUUABSAQAHAAcJkBGUUABSAQAAAA==.Thraell:BAAALgAECgEJAQAAAA==.',
Ti='Tigerblood:BAAALgADCgUJBQAAAA==.Tipooreeii:BAAALgADCgEJAQAAAA==.Titanicos:BAAALgAFFAEJAQAAAA==.',
Tj='Tjhunter:BAABLgAECn8fAAIBAAgJnQpeSQCNAQABAAgJnQpeSQCNAQAAAA==.',
To='Tobbiy:BAAALgAFFAIJBAAAAA==.Toddyb:BAAALgAECggJCwAAAA==.Tonytornado:BAAALgAECgEJAgAAAA==.',
Tr='Tranh:BAAALgADCgkJFQAAAA==.Traxer:BAAALgADCgQJBAAAAA==.Tripäsecä:BAAALgAECgYJDAAAAA==.Troladora:BAABLgAECn8VAAIFAAYJqA7NtgD6AAAFAAYJqA7NtgD6AAAAAA==.Trévor:BAAALgAECgEJAQAAAA==.',
Ts='Tsreis:BAAALgADCgEJAQAAAA==.',
Tw='Twoheavy:BAAALgADCgkJCQABLgAECgYJCQAGAAAAAA==.',
Ty='Tyrandrisa:BAAALgADCgIJAQAAAA==.',
['Tá']='Tátu:BAAALgADCgMJAwAAAA==.',
Uh='Uhdyr:BAAALgAECgQJBAAAAA==.',
Um='Ummetrodefio:BAAALgADCgEJAQAAAA==.',
Ut='Uthred:BAABLgAECn8vAAQUAAkJHQf/jQA1AQAUAAkJcwT/jQA1AQAiAAYJqgRvDADrAAAVAAMJrgk8QwBmAAAAAA==.',
Va='Vaelryn:BAAALgAECgUJCAABLgAECgYJBgAGAAAAAA==.Valdemmon:BAAALgAECgQJBwAAAA==.Valororo:BAAALgAECgcJEwAAAA==.Vandlesh:BAAALgAECgYJDwAAAA==.Vardha:BAAALgADCgQJBAAAAA==.Varka:BAAALgADCgYJGQAAAA==.',
Ve='Velkharun:BAAALgAECgQJCwABLgAFFAIJAwAGAAAAAA==.Velkryon:BAAALgAECgEJAQAAAA==.Venatrin:BAAALgADCgkJCQAAAA==.Vess:BAAALgAECgQJBAAAAA==.Vexxv:BAABLgAECn8UAAIUAAUJshqnigBrAQAUAAUJshqnigBrAQAAAA==.Vexxz:BAAALgAECgYJBwAAAA==.',
Vi='Viquue:BAAALgADCgYJBgAAAA==.Vivisoft:BAAALgADCgMJAwAAAA==.',
Vl='Vlannytic:BAAALgAECgEJAQAAAA==.',
Vo='Voidrb:BAAALgADCgcJBwABLgAECggJFAAKAEcYAA==.Vovogamer:BAAALgAECgQJBAAAAA==.',
['Vò']='Vòxs:BAACLgAFFH8SAAMQAAQJohRCGgDrAAAQAAMJhxhCGgDrAAAKAAIJug+9OACVAAAuAAQKf0sAAxAACAk8JLYDAMQCABAABwnDJLYDAMQCAAoABglHHoQuAPcBAAAA.',
Wa='Walkery:BAAALgADCgIJAgAAAA==.Wattari:BAABLgAECn8bAAIPAAYJDgTvNQCIAAAPAAYJDgTvNQCIAAAAAA==.Watters:BAAALgAECgUJCQABLgAFFAMJBwAdAEIMAA==.',
Wh='Whiteep:BAAALgADCgYJCAAAAA==.Whiteseraph:BAAALgADCgEJAQAAAA==.Whynchester:BAAALgADCgEJAQAAAA==.',
Wi='Wiilami:BAAALgADCgMJAwAAAA==.Windsailor:BAAALgAECgUJBQAAAA==.Wiserys:BAACLgAFFH8FAAIMAAMJKA5XcADKAAAMAAMJKA5XcADKAAAuAAQKfywAAw0ABwk6ISMJALIBAAwABglYIUlAAM8BAA0ABgn+HCMJALIBAAAA.',
Wm='Wmarcão:BAABLgAECn8YAAMLAAcJbw3WEwD1AAALAAYJlA/WEwD1AAAMAAcJYAX2sgDUAAAAAA==.',
Wo='Wolfiez:BAAALgAECgUJDAAAAA==.Wolfnwar:BAAALgAECgQJDgAAAA==.Wopz:BAAALgADCgcJBwAAAA==.Worq:BAAALgADCgYJBgAAAA==.',
Wq='Wqz:BAABLgAECn8VAAIBAAcJWhmTNgDUAQABAAcJWhmTNgDUAQAAAA==.',
Wu='Wunamuno:BAAALgAECgEJAQAAAA==.',
Xa='Xallatath:BAAALgADCgUJBQAAAA==.Xamela:BAAALgADCgMJAwAAAA==.Xamãna:BAAALgAECgQJCQAAAA==.',
Xe='Xevron:BAAALgAECgQJBAAAAA==.Xexnetw:BAAALgAECgQJCgAAAA==.Xexnew:BAABLgAECn8ZAAMVAAkJ9Bo9DQAcAgAVAAkJ9Bo9DQAcAgAUAAEJaQdHZQEnAAAAAA==.',
Xf='Xframengox:BAAALgADCgEJAQAAAA==.',
Xi='Xidevill:BAAALgAECgYJDQAAAA==.Xinthorak:BAAALgADCgEJAgAAAA==.Xinzhou:BAAALgADCgQJCAAAAA==.Xiseth:BAAALgAECgIJAgAAAA==.Xixíca:BAAALgADCgUJBgAAAA==.',
Xm='Xmari:BAAALgAECgYJBwAAAA==.',
Xn='Xnyx:BAAALgAECgEJAQAAAA==.',
Xu='Xulaman:BAAALgAECgcJDgAAAA==.Xungodz:BAAALgADCgQJBAAAAA==.Xunxu:BAABLgAECn8ZAAMDAAYJdhMQhwBsAQADAAYJdhMQhwBsAQAlAAEJJgM2ngArAAAAAA==.',
Xx='Xxcantsidex:BAAALgAECgEJAQAAAA==.',
Xy='Xynrath:BAAALgADCgMJAwAAAA==.',
['Xÿ']='Xÿon:BAAALgAECgEJAQAAAA==.',
Ya='Yamëte:BAAALgAECgQJBQAAAA==.Yannadcg:BAACLgAFFH8GAAIWAAQJ9gLAGwC4AAAWAAQJ9gLAGwC4AAAuAAQKfy4AAhYACQmRCwElAIYBABYACQmRCwElAIYBAAAA.',
Yo='Yorickundyer:BAAALgAECgIJAwAAAA==.Youdie:BAABLgAECn8YAAIgAAgJhRLwKgCEAQAgAAgJhRLwKgCEAQAAAA==.',
Yu='Yulthuan:BAAALgADCgMJAwAAAA==.',
Yv='Yvernus:BAAALgAECgQJBgAAAA==.',
Yz='Yziepala:BAAALgAECgMJBAAAAA==.',
Za='Zaaraki:BAABLgAECn8wAAMUAAkJ6RiUTQDHAQAUAAkJdReUTQDHAQAVAAcJoRY8HgBKAQAAAA==.Zarolho:BAABLgAECn8VAAIIAAYJSA6EUAAFAQAIAAYJSA6EUAAFAQAAAA==.',
Ze='Zenitsua:BAAALgAECgYJCQAAAA==.Zenzeluk:BAAALgAECgMJAwAAAA==.Zephiir:BAABLgAECn8ZAAIDAAYJExVcjgA5AQADAAYJExVcjgA5AQAAAA==.Zeroxyz:BAAALgADCgYJBgABLgAECgYJEwAGAAAAAA==.Zeryen:BAAALgAECgEJAQAAAA==.',
Zh='Zhunka:BAAALgADCgEJAgAAAA==.',
Zo='Zornak:BAAALgADCgUJBQAAAA==.',
Zz='Zzx:BAAALgADCgcJBwAAAA==.',
['Zé']='Zécasete:BAAALgADCgUJBwAAAA==.',
['Ál']='Álucard:BAABLgAECn8VAAIUAAcJNAoqkgAuAQAUAAcJNAoqkgAuAQAAAA==.',
['Ån']='Åntares:BAAALgADCgMJAwAAAA==.',
['Éy']='Éyga:BAAALgAECgEJBAAAAA==.',
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
