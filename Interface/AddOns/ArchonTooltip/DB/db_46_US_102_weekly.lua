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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Paladin-Retribution','Paladin-Protection','Mage-Frost','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Fury','Hunter-Survival','Warrior-Protection','Warrior-Arms','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Priest-Holy','DemonHunter-Devourer','Monk-Windwalker','DemonHunter-Vengeance','Druid-Balance','Mage-Arcane','Hunter-Marksmanship','Priest-Discipline','Mage-Fire','DeathKnight-Blood','Monk-Mistweaver','Priest-Shadow','DemonHunter-Havoc','DeathKnight-Frost','Paladin-Holy','Druid-Feral','Monk-Brewmaster',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abortheira:BAAALgADCgUJBQAAAA==.',
Ac='Acelord:BAABLgAECn8eAAIBAAkJcRUXJwAYAgABAAkJcRUXJwAYAgAAAA==.Actaeon:BAAALgAECgQJBAAAAA==.',
Ad='Adaar:BAAALgAECgEJAQAAAA==.Adadebox:BAAALgAECgEJAQAAAA==.Adakat:BAAALgADCgEJAQAAAA==.Adanthedark:BAAALgADCgIJAgAAAA==.Adariom:BAAALgADCgUJCAAAAA==.Adrian:BAAALgADCgEJAQAAAA==.Adriannos:BAAALgAECgEJAQAAAA==.',
Ae='Aethir:BAAALgADCgYJBwAAAA==.',
Ag='Agonyy:BAAALgAECgUJDQAAAA==.Agrias:BAAALgAECgEJAQAAAA==.',
Ah='Aharadack:BAAALgADCgUJCwAAAA==.',
Ak='Akawaka:BAAALgAECgEJAQAAAA==.Akiji:BAAALgAECgEJAgAAAA==.Akimurad:BAAALgAECgYJBgAAAA==.',
Al='Alakazam:BAAALgADCgcJBwAAAA==.Alanie:BAAALgADCggJCAABLgAECggJIwACABUeAA==.Ald:BAAALgAECgEJAgAAAA==.Aldebaraum:BAAALgAECgEJAgAAAA==.Alexextreme:BAAALgAECgcJEQAAAA==.Alikth:BAAALgADCgYJBgAAAA==.Alista:BAAALgAECgMJAgAAAA==.Allandyr:BAABLgAECn8yAAIBAAgJARcDPADEAQABAAgJARcDPADEAQAAAA==.Alvarao:BAAALgAECgQJBAAAAA==.',
Am='Amandadark:BAAALgAECgEJAQAAAA==.Amano:BAAALgADCgYJDAAAAA==.',
An='Anaxthacia:BAAALgADCgMJAwAAAA==.Andinth:BAAALgADCgQJBAAAAA==.Andrepvp:BAAALgADCggJDwAAAA==.Andrit:BAAALgADCgEJAQAAAA==.Anellÿ:BAAALgAECgEJAQAAAA==.Angelloz:BAABLgAECn8nAAIDAAgJxhD3aQB7AQADAAgJxhD3aQB7AQAAAA==.Anjelvs:BAAALgAECgYJBgAAAA==.Annaoh:BAABLgAECn8cAAIDAAgJVB1HMgAWAgADAAgJVB1HMgAWAgAAAA==.Annia:BAAALgADCgYJBwAAAA==.Anyid:BAAALgAECgMJAwAAAA==.Anãodengoso:BAABLgAECn8pAAMDAAgJSCZgFQDpAgADAAgJSCZgFQDpAgAEAAIJIxJzMwBnAAABLgAECggJKQADAEgmAA==.',
Ap='Apökalÿpsïs:BAABLgAECn8UAAIFAAYJNAoyuAD5AAAFAAYJNAoyuAD5AAAAAA==.',
Ar='Arator:BAAALgAECggJCgAAAA==.Ardry:BAAALgADCgYJBgAAAA==.Argaloth:BAAALgAECgYJBwAAAA==.Argonzinha:BAAALgADCgIJAgAAAA==.',
As='Ashthon:BAABLgAECn8eAAIBAAcJgxyqQQCxAQABAAcJgxyqQQCxAQAAAA==.Asmitta:BAAALgADCgQJBAAAAA==.',
At='Atomictank:BAAALgAECgcJEwAAAA==.Atonos:BAAALgAECgcJCwAAAA==.',
Au='Augustosg:BAAALgAECgYJCwABLgAECgYJDgAGAAAAAA==.Auquenai:BAAALgADCgUJBQAAAA==.Aurielis:BAAALgAECgEJAgAAAA==.',
Av='Averagemage:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAAALgAECgQJBAAAAA==.',
Az='Azadium:BAAALgAECgUJCgAAAA==.Azul:BAAALgAECgQJBgAAAA==.',
Ba='Badayaga:BAAALgADCgIJAgAAAA==.Bakunogrind:BAAALgAECgUJBQABLgAFFAQJBwAHAEMeAA==.Balthar:BAABLgAECn8gAAQIAAcJOhIkPQAQAQAIAAcJoxEkPQAQAQAJAAQJChFrHQD1AAAHAAQJBg8CjQB3AAAAAA==.Barathrum:BAAALgADCgEJAQAAAA==.Barcaldas:BAAALgAECgUJBgAAAA==.Barrocø:BAAALgAECgQJBQABLgAECggJEQAGAAAAAA==.Basara:BAAALgAECgYJDwAAAA==.Batefraco:BAAALgADCgIJAgAAAA==.',
Bb='Bbiel:BAABLgAECn8hAAMKAAUJwBUPEwDtAAAKAAUJwBUPEwDtAAALAAEJ3wHnNQEfAAAAAA==.',
Be='Beatriz:BAAALgAECgYJCQAAAA==.Beelgarath:BAAALgAECgMJBgAAAA==.Beherit:BAAALgADCgMJBwAAAA==.Beliall:BAAALgADCgQJBQAAAA==.Belowlight:BAAALgADCgYJEQAAAA==.Belttazar:BAAALgADCgkJDwAAAA==.Bemmaith:BAAALgAECgQJBAAAAA==.Berzan:BAAALgAECgQJBwAAAA==.Beyoond:BAACLgAFFH8VAAMLAAQJrxUAVwDqAAALAAMJFBUAVwDqAAAMAAEJgBe9EwBTAAAuAAQKfzoABAsACQm+HM4dAFgCAAsACQm/G84dAFgCAAoABAm3D+cxAPEAAAwAAwnBFowXAMwAAAAA.',
Bh='Bhalin:BAAALgAECgQJBAAAAA==.',
Bi='Bielinski:BAAALgAECgQJBAAAAA==.',
Bl='Blackdut:BAAALgAFFAEJAgAAAA==.Blackrøse:BAAALgADCgYJBgAAAA==.Blackteriaa:BAAALgAECgUJDwAAAA==.Blacrapumzel:BAAALgAECgMJAwAAAA==.Blankis:BAAALgADCgYJCQAAAA==.Blizther:BAAALgADCgIJAgAAAA==.Bloodh:BAAALgAECgEJAwAAAA==.Bls:BAAALgADCgMJAwAAAA==.',
Bo='Boijf:BAAALgADCgEJAQAAAA==.Boladomal:BAAALgAECgMJAwAAAA==.Bones:BAAALgAECgEJAQAAAA==.Boromy:BAAALgAECgEJAgAAAA==.Boruck:BAAALgAECgIJAwAAAA==.',
Br='Braandom:BAAALgAECgcJDAAAAA==.Bradan:BAABLgAECn8eAAINAAgJURWcKgAOAgANAAgJURWcKgAOAgAAAA==.Brandomm:BAAALgAECgYJDQAAAA==.Branmir:BAAALgAECgMJBgAAAA==.Bridda:BAAALgAECgYJDAAAAA==.Brolho:BAAALgADCgEJAQAAAA==.Brusque:BAAALgAECgcJBwAAAA==.Bruzapaladin:BAAALgADCgUJBQAAAA==.',
Bt='Btrcaotics:BAAALgAECgIJBwAAAA==.Btrguard:BAAALgAECgIJAgAAAA==.',
['Bé']='Béto:BAAALgAECgMJBAAAAA==.',
['Bí']='Bíbs:BAABLgAECn8VAAIBAAgJkRMsQgCwAQABAAgJkRMsQgCwAQAAAA==.',
Ca='Cabanagé:BAAALgAECgUJBwAAAA==.Cabeludometa:BAAALgAECgEJAgAAAA==.Cabodecobre:BAAALgAECgUJCwAAAA==.Cainmarko:BAAALgAECgYJEAAAAA==.Caiowisk:BAABLgAECn8UAAMLAAcJFwU4nQDtAAALAAcJFwU4nQDtAAAKAAEJAACpSQAAAAAAAA==.Calir:BAAALgADCgYJFgAAAA==.Calçadora:BAABLgAECn8+AAIOAAkJlSEMBADYAgAOAAkJlSEMBADYAgAAAA==.Cardrok:BAAALgADCgEJAQAAAA==.Caridosa:BAAALgADCgUJBQAAAA==.Carnius:BAABLgAECn9CAAQPAAgJRx5HDQDuAQAPAAgJIR1HDQDuAQANAAIJuiAIewBMAAAQAAEJDxz1VgBDAAAAAA==.Casipala:BAAALgAECgIJAgAAAA==.Casuall:BAAALgAECgcJBwAAAA==.Cataclysm:BAAALgAECgMJBAAAAA==.Catalango:BAAALgAECgQJCgAAAA==.Catapó:BAAALgAECgQJCgAAAA==.Catapózão:BAABLgAECn8vAAICAAgJFCGyCgDzAgACAAgJFCGyCgDzAgAAAA==.Catü:BAAALgAECgEJAQAAAA==.Cavernus:BAAALgADCgMJAwAAAA==.Caves:BAAALgADCgIJAgAAAA==.Caveston:BAAALgADCgUJCgAAAA==.',
Cb='Cbestabr:BAAALgADCgYJBgAAAA==.',
Ch='Chamadmordor:BAAALgAECgMJBQAAAA==.Charats:BAAALgADCgYJDQAAAA==.Charterine:BAAALgADCgYJBgAAAA==.Chaya:BAAALgADCgUJBQAAAA==.Chicknorris:BAAALgADCgUJBQAAAA==.Chifrudaxl:BAAALgAECgMJAwAAAA==.Chrisjks:BAAALgADCgYJCgAAAA==.',
Ci='Cindyn:BAAALgAECgEJAQAAAA==.',
Cl='Clared:BAAALgADCgEJAQAAAA==.Clebeya:BAAALgADCgQJBAAAAA==.Climps:BAABLgAECn8WAAIBAAgJRRcSLQD/AQABAAgJRRcSLQD/AQAAAA==.',
Co='Cobyx:BAAALgADCgcJDAAAAA==.Cocaferoz:BAAALgADCgEJAQAAAA==.Coffeeaddict:BAAALgADCgMJAwAAAA==.Colugo:BAAALgADCgIJAgAAAA==.Coriisco:BAAALgADCgIJAgAAAA==.Corollaxei:BAABLgAECn80AAQRAAkJsxfiCQAiAgARAAkJsxfiCQAiAgASAAQJYgrcUADAAAATAAEJWAxgIAA1AAAAAA==.Cosculluela:BAAALgADCgUJBwAAAA==.Cosmuh:BAAALgAECgEJAQAAAA==.',
Cr='Creuzapriest:BAAALgAECgEJAQAAAA==.Crookedyoung:BAAALgAECgEJAwABLgAECgcJDwAGAAAAAA==.Cruzade:BAAALgAECgcJEgABLgAFFAEJAQAGAAAAAA==.Cröwllëy:BAABLgAECn8hAAIUAAgJnBcvPADuAQAUAAgJnBcvPADuAQAAAA==.',
Cu='Cubatao:BAABLgAECn8UAAIBAAYJUxTDbAA6AQABAAYJUxTDbAA6AQAAAA==.Cucaracha:BAAALgAECgUJDwAAAA==.',
Da='Dahhak:BAAALgAECgUJCwAAAA==.Dakhgagul:BAAALgADCgUJBQAAAA==.Dakshayani:BAAALgAECgQJBAAAAA==.Danielbrz:BAAALgAECgMJAwAAAA==.Daniellpvp:BAAALgADCgEJAQAAAA==.Danygatuxa:BAAALgAECgUJDQAAAA==.Dardano:BAAALgAECgEJAQAAAA==.Daree:BAAALgAECgEJAQAAAA==.Darkenes:BAAALgAECgEJAQAAAA==.Darkinmt:BAAALgADCgcJCAAAAA==.Darknesstk:BAAALgAECgYJDgAAAA==.Darksiderptc:BAAALgADCgcJDwAAAA==.Darthmansur:BAAALgAECgYJCQAAAA==.',
De='Deadvi:BAAALgAECggJEQAAAA==.Deadziin:BAAALgAECgYJDwAAAA==.Deathmäsk:BAAALgADCgcJBwAAAA==.Demetrix:BAAALgADCgkJCgAAAA==.Dennyam:BAAALgAECgYJCQAAAA==.Derothey:BAABLgAECn8pAAIFAAgJYBa5SgDfAQAFAAgJYBa5SgDfAQAAAA==.Deservis:BAAALgADCgYJBgAAAA==.Deulorem:BAACLgAFFH8MAAIVAAQJZx38CgBgAQAVAAQJZx38CgBgAQAuAAQKfzMAAhUACQlgHikEACcDABUACQlgHikEACcDAAAA.Devilblade:BAABLgAECn8RAAIWAAgJXgmljwACAQAWAAgJXgmljwACAQAAAA==.',
Di='Diabolynn:BAAALgAECgYJBgAAAA==.',
Dk='Dkatraia:BAAALgAECgMJAwAAAA==.',
Dn='Dngfafinir:BAAALgAECggJBwABLgAFFAUJDAADAFgXAA==.Dnghidan:BAACLgAFFH8MAAIDAAUJWBfhKgA6AQADAAUJWBfhKgA6AQAuAAQKfygAAgMACQmrHvohAKICAAMACQmrHvohAKICAAAA.Dngtobi:BAAALgAECgUJCQABLgAFFAUJDAADAFgXAA==.',
Do='Dollynhø:BAABLgAECn8dAAIXAAgJAhrxEwD1AQAXAAgJAhrxEwD1AQAAAA==.Donyed:BAAALgAECgQJCAAAAA==.Dottado:BAAALgADCgcJCgAAAA==.',
Dr='Drackah:BAAALgADCgcJBwAAAA==.Draconían:BAAALgAECgEJBwAAAA==.Dracón:BAAALgAECgUJBQAAAA==.Draigo:BAAALgAECgIJAgAAAA==.Dreykar:BAABLgAECn8qAAMWAAkJDBYWJQAbAgAWAAkJDBYWJQAbAgAYAAEJ2Bz/JABOAAAAAA==.Drogorn:BAAALgAECgUJCwAAAA==.Druidaezeki:BAAALgADCgYJCwAAAA==.Druidjm:BAAALgADCgMJAwAAAA==.Druvannar:BAAALgADCgEJAQAAAA==.Dröwränger:BAAALgADCgEJAQAAAA==.',
Du='Dultrasenegl:BAABLgAECn8eAAIBAAYJAA3yZQA2AQABAAYJAA3yZQA2AQAAAA==.Dunois:BAAALgAECgIJBgAAAA==.',
['Dä']='Dähäkä:BAABLgAECn8cAAIDAAgJsRxRJwBEAgADAAgJsRxRJwBEAgAAAA==.',
Ed='Edven:BAACLgAFFH8OAAIRAAMJRgO4HACcAAARAAMJRgO4HACcAAAuAAQKfyEAAhEABgnKDMYlAEgBABEABgnKDMYlAEgBAAAA.',
El='Elbruxão:BAAALgAECgEJAQAAAA==.Eldrick:BAAALgADCgIJAgAAAA==.Eldros:BAAALgAECgYJCAAAAA==.Elementais:BAAALgAECgYJEgAAAA==.Elgado:BAAALgAECgEJAwAAAA==.Elgatadexota:BAAALgADCgkJCgAAAA==.Eliksir:BAAALgAECgUJBQAAAA==.Ellanor:BAABLgAECn8cAAIFAAgJ+hgASADoAQAFAAgJ+hgASADoAQAAAA==.Elruth:BAAALgADCggJCAABLgAFFAQJDAAVAGcdAA==.Eltão:BAAALgAECgEJAQAAAA==.Elunah:BAAALgADCgQJBAAAAA==.Elwindor:BAAALgAECgEJAQAAAA==.Elyind:BAAALgADCgYJBgAAAA==.',
Em='Emmymm:BAAALgADCgIJAgAAAA==.',
En='Endeavour:BAAALgADCgEJAQAAAA==.Enegadiel:BAABLgAECn8cAAIDAAcJIg9ZhgBCAQADAAcJIg9ZhgBCAQAAAA==.Enoia:BAAALgADCgcJDQAAAA==.',
Eq='Equidnah:BAAALgAECgIJAgAAAA==.',
Er='Erickya:BAAALgAECggJEAAAAA==.Ervadocè:BAABLgAECn8ZAAIZAAYJwhi4LABCAQAZAAYJwhi4LABCAQAAAA==.Ervelino:BAAALgAECgMJBAAAAA==.',
Es='Estrogosbald:BAABLgAECn8ZAAIaAAgJMQwtBQBiAQAaAAgJMQwtBQBiAQAAAA==.',
Ev='Evely:BAABLgAECn8aAAIbAAcJgxgiDAB8AQAbAAcJgxgiDAB8AQAAAA==.',
Ex='Exarch:BAACLgAFFH8NAAIOAAQJaRQrDQBFAQAOAAQJaRQrDQBFAQAuAAQKfyoAAg4ACQm/ISQCABUDAA4ACQm/ISQCABUDAAAA.',
Fa='Faengar:BAAALgAECgUJCAAAAA==.Falcondk:BAAALgAECgEJAQAAAA==.Falconess:BAAALgADCgEJAQAAAA==.',
Fe='Feathria:BAAALgAECgMJAwAAAA==.Felipebritoo:BAAALgAECgMJBgABLgAECgYJEQAGAAAAAA==.Fenrirsp:BAAALgAFFAIJAwAAAA==.Ferdruiid:BAAALgADCgkJEwAAAA==.Feropudo:BAAALgADCgkJDgAAAA==.Ferrarig:BAAALgAECgEJBQAAAA==.',
Fi='Figy:BAAALgAECgQJBAAAAA==.',
Fl='Flemma:BAABLgAECn8YAAIRAAgJJgfIGQAVAQARAAgJJgfIGQAVAQAAAA==.Flexer:BAAALgAECgIJAgAAAA==.Flores:BAAALgADCgMJBQAAAA==.Floridastyle:BAABLgAECn8fAAIcAAUJTxYrLgA6AQAcAAUJTxYrLgA6AQAAAA==.',
Fo='Foguerosa:BAACLgAFFH8JAAMFAAMJpRyQLwD4AAAFAAMJpRyQLwD4AAAdAAEJggAtBAA7AAAuAAQKfxYAAgUACAlpIVREAGsCAAUACAlpIVREAGsCAAAA.Folghunthir:BAAALgADCgQJBAAAAA==.',
Fr='Frankkquini:BAAALgADCgYJEgAAAA==.Friodokrl:BAABLgAECn82AAMeAAkJBx4mCwAvAgAeAAkJLhsmCwAvAgAUAAgJHRoYOAD8AQAAAA==.Fritzgerhart:BAAALgAECgEJAQAAAA==.Frostmhaw:BAAALgADCgUJBQAAAA==.Frostreaper:BAAALgAECgQJBgAAAA==.',
Fu='Fubukiofhell:BAABLgAECn8ZAAIFAAcJsBrUTQDVAQAFAAcJsBrUTQDVAQAAAA==.Fuginzao:BAAALgAECgEJAQAAAA==.Furtacor:BAAALgADCgcJBwAAAA==.Furyarh:BAAALgAECgMJAwAAAA==.',
['Fí']='Fí:BAAALgADCggJDgABLgAECgkJHQABALAaAA==.',
Ga='Gabana:BAAALgADCgQJBAAAAA==.Gabdobbuh:BAAALgAECgUJCAAAAA==.Gabn:BAAALgAECgIJAwAAAA==.Gafgar:BAAALgADCgUJCQAAAA==.Gaila:BAAALgAECgIJBgAAAA==.Galduin:BAABLgAECn8rAAINAAkJ5xPxGQD6AQANAAkJ5xPxGQD6AQAAAA==.',
Ge='Gedexx:BAAALgAECgMJAgAAAA==.Geduntruppa:BAAALgAECgYJBgAAAA==.Gentioiroh:BAAALgAECgMJAwAAAA==.',
Gh='Ghorderp:BAAALgADCgcJDAAAAA==.Ghosstt:BAAALgAECgEJAgAAAA==.Ghoulrozon:BAAALgADCgYJBgAAAA==.',
Gi='Giovannapala:BAABLgAECn8XAAIDAAgJ/A0igwBIAQADAAgJ/A0igwBIAQAAAA==.Giripoca:BAAALgAECgQJCQAAAA==.',
Gl='Gladsmonge:BAABLgAECn8fAAIfAAcJCh3SFgALAgAfAAcJCh3SFgALAgAAAA==.Glorcckk:BAAALgAECgMJAwAAAA==.',
Gn='Gnomagga:BAAALgAECgcJEAABLgAECggJNgAEAB8cAA==.Gnomohabe:BAAALgADCgQJBgAAAA==.',
Go='Goddofwarr:BAAALgADCggJEQAAAA==.Gonb:BAAALgADCgUJBQAAAA==.Goueki:BAABLgAECn8oAAMBAAgJHBd6NwDVAQABAAgJHBd6NwDVAQAbAAIJSwEtgwA8AAAAAA==.',
Gr='Greenzle:BAAALgAECgUJBgAAAA==.Grillnborst:BAAALgADCgEJAgAAAA==.Grilonp:BAAALgADCgQJCAAAAA==.Grogath:BAAALgAECgMJBQAAAA==.Grogtixa:BAAALgAECggJCQABLgAECgkJKgAIAFcWAA==.Gromoff:BAABLgAFFH8GAAILAAIJuh9OdQCjAAALAAIJuh9OdQCjAAAAAA==.Grunmonk:BAAALgADCgEJAQAAAA==.Grømmar:BAAALgADCgMJAwAAAA==.',
Gu='Gudangara:BAAALgADCgYJBgAAAA==.Gumy:BAAALgAECgEJAgAAAA==.Guztaverdead:BAAALgADCgQJBAAAAA==.',
['Gü']='Güistrong:BAAALgADCgIJAwAAAA==.',
Ha='Haakaí:BAAALgAECgUJDQAAAA==.Haandir:BAAALgAECgIJAgAAAA==.Hackterin:BAAALgADCgYJBgAAAA==.Hadorah:BAAALgAECgUJBgAAAA==.Haerys:BAAALgADCgYJBgAAAA==.Handhemirr:BAAALgAECgMJBAAAAA==.Harany:BAABLgAECn8cAAMcAAgJlw+dJQBzAQAcAAgJlw+dJQBzAQAgAAUJQAp+SQC6AAAAAA==.Harrypotinho:BAABLgAECn8sAAILAAgJ5RZKOgDYAQALAAgJ5RZKOgDYAQAAAA==.Haunexd:BAAALgADCgMJAwAAAA==.Havenna:BAAALgAECgUJCAAAAA==.',
He='Headøhunter:BAAALgAECgEJAgAAAA==.Healgate:BAAALgAECgEJAQAAAA==.Heeythaly:BAAALgADCgcJDAAAAA==.Hellenah:BAAALgADCggJCAAAAA==.Herablack:BAAALgAECgEJAQAAAA==.Herika:BAAALgADCgMJAwAAAA==.',
Ho='Hoem:BAAALgAECgMJAwAAAA==.Holand:BAAALgAECgYJDAAAAA==.Holydread:BAAALgAECgIJAgAAAA==.',
Hu='Hulig:BAABLgAECn8kAAIDAAgJgh17JgBIAgADAAgJgh17JgBIAgABLgAFFAEJAQAGAAAAAA==.Hunthearthas:BAAALgAECgMJAwAAAA==.',
['Hø']='Høkulani:BAABLgAECn8bAAIFAAcJHhGweABqAQAFAAcJHhGweABqAQAAAA==.',
Ib='Ibrad:BAAALgAECgQJBAAAAA==.Ibuprofens:BAAALgAECgEJAQAAAA==.',
Ic='Iceyag:BAAALgAECgIJAgAAAA==.',
Ik='Ikiam:BAAALgAECgQJBQAAAA==.Ikslawok:BAAALgADCgYJEAAAAA==.',
Il='Ileria:BAAALgAECgYJBwAAAA==.Iliriana:BAAALgADCgQJBwAAAA==.Illarion:BAAALgADCgQJBAAAAA==.Illidanos:BAABLgAECn8aAAIhAAgJ/RHIGACEAQAhAAgJ/RHIGACEAQAAAA==.Illidansan:BAAALgAECgQJBQABLgAECgUJCgAGAAAAAA==.Illidris:BAAALgAECgUJBQAAAA==.Illumiinated:BAAALgAECgYJEgAAAA==.',
In='Incarus:BAAALgAECgcJCgAAAA==.Indis:BAAALgADCgQJBgAAAA==.Interst:BAAALgAECgEJAQAAAA==.',
Ir='Irion:BAAALgAECgIJAgAAAA==.',
Is='Iscalio:BAAALgAECgYJCQAAAA==.',
It='Itatchii:BAAALgADCgkJCQAAAA==.',
Iv='Ivinhosilva:BAAALgADCgYJBgAAAA==.',
Ja='Jackdawnsong:BAAALgAECgcJCgAAAA==.Jaene:BAAALgADCgYJCQAAAA==.Jahuun:BAABLgAECn8UAAIDAAcJbQtXkQAvAQADAAcJbQtXkQAvAQAAAA==.Jamantoso:BAAALgAECgEJAQAAAA==.',
Je='Jeess:BAAALgADCgMJAwAAAA==.Jefflich:BAABLgAECn8iAAMUAAgJ4AqUiQBuAQAUAAgJiwmUiQBuAQAiAAEJhxJpKwAvAAAAAA==.',
Jg='Jg:BAAALgAECgUJBwABLgAECgYJDgAGAAAAAA==.',
Ji='Jinknu:BAAALgAECgIJBAAAAA==.',
Jo='Jottapeg:BAAALgADCgcJAwAAAA==.',
Ju='Jubard:BAAALgADCgkJDAAAAA==.Juliamarques:BAAALgAECgMJBAAAAA==.',
['Jü']='Jüllÿe:BAAALgADCgEJAQAAAA==.',
Ka='Kaaellthas:BAAALgAECgQJCQAAAA==.Kacolux:BAAALgADCgEJAQAAAA==.Kaisaargente:BAAALgAECgEJAQAAAA==.Kakarotho:BAAALgAECgMJCQAAAA==.Kalarath:BAAALgAECgYJBgAAAA==.Kaldonios:BAAALgADCgcJEgAAAA==.Kamasutram:BAAALgADCgYJCwAAAA==.Kanadriel:BAAALgAECgcJDAAAAA==.Kanarinho:BAABLgAECn8uAAICAAkJIh8SBwArAwACAAkJIh8SBwArAwAAAA==.Karmussie:BAAALgADCgEJAQAAAA==.Katari:BAAALgAECgYJCgABLgAECgkJIAAjAAMfAA==.Kayanz:BAAALgADCgUJBQAAAA==.Kazandra:BAAALgADCgYJBgAAAA==.',
Ke='Kendars:BAABLgAECn8VAAQZAAYJ0xKfSAAKAQAZAAUJJhKfSAAKAQACAAUJFQ+5dgDzAAAkAAEJhRXeNwBDAAABLgAFFAMJBwAeALAMAA==.Ket:BAAALgADCgMJAwAAAA==.',
Kh='Khanmir:BAAALgAECgMJBgAAAA==.Kharon:BAAALgAECgYJBgAAAA==.Khild:BAAALgAECgYJDQAAAA==.Khonar:BAAALgADCgUJBgAAAA==.',
Ki='Killerdek:BAAALgAECgUJBQAAAA==.Killshoty:BAAALgAECgEJAgAAAA==.',
Kk='Kkiara:BAAALgAECgIJAgAAAA==.',
Kl='Klissera:BAAALgADCgQJBAAAAA==.Kluzlocak:BAABLgAECn8iAAIcAAYJUQzPMQAlAQAcAAYJUQzPMQAlAQAAAA==.',
Kn='Knnabys:BAAALgAECgEJAQAAAA==.',
Ko='Komah:BAAALgAECgEJAQAAAA==.Korav:BAAALgAECgMJCQAAAA==.Korium:BAAALgADCgUJBQABLgAECgkJLQAPAIshAA==.Koruno:BAAALgADCgYJBgAAAA==.',
Kr='Krosn:BAAALgAECgEJAQAAAA==.Krozhul:BAAALgAECgQJBwAAAA==.',
Ku='Kurnous:BAAALgAECgEJAQAAAA==.Kutirenzo:BAAALgADCgUJBwAAAA==.',
La='Lafiel:BAAALgAECgcJEQAAAA==.Lagertha:BAAALgADCgYJBgAAAA==.Lambayoda:BAAALgAECgYJBwAAAA==.Lamelo:BAAALgADCgYJBgAAAA==.Lanmo:BAAALgAECgcJAgAAAA==.Largatixazul:BAAALgADCgUJBgAAAA==.Lataria:BAAALgADCgEJAQAAAA==.Laurea:BAAALgAECgYJBgABLgAECgkJIAAjAAMfAA==.',
Le='Leebron:BAAALgAECgYJDAAAAA==.Lefthalas:BAAALgAECgUJCgAAAA==.Leitchero:BAAALgAECgIJAgAAAA==.Lemaz:BAAALgAECgEJAQAAAA==.Leonelmessi:BAAALgAFFAQJAQAAAA==.Lesco:BAAALgADCgMJAwAAAA==.',
Li='Lianele:BAAALgAECgYJCQAAAA==.Liaras:BAABLgAECn8pAAMVAAgJXBfCGADfAQAVAAgJXBfCGADfAQAgAAIJzABFaQAmAAAAAA==.Libertinagem:BAAALgAECgYJCgAAAA==.Lichtbaum:BAABLgAECn8VAAMCAAgJyhxaIABAAgACAAgJyhxaIABAAgAZAAMJORAeUwCRAAAAAA==.Lightsertrop:BAAALgADCgIJAgAAAA==.Liifecomm:BAACLgAFFH8MAAIVAAQJSxfqDQA3AQAVAAQJSxfqDQA3AQAuAAQKfzUAAhUACQniHVkNAIICABUACQniHVkNAIICAAAA.Liike:BAAALgAECgcJCwAAAA==.Linestra:BAAALgADCgUJBQAAAA==.Liniak:BAAALgAECgcJDwAAAA==.Lisong:BAAALgADCgUJBQAAAA==.Littlepurple:BAACLgAFFH8JAAIWAAMJzxJ7GwD2AAAWAAMJzxJ7GwD2AAAuAAQKfyQAAhYACQl0HJwYAMICABYACQl0HJwYAMICAAAA.',
Lo='Longhai:BAAALgADCgUJCAAAAA==.Lookatmylock:BAABLgAECn8iAAMKAAYJ/xufCQB/AQAKAAYJ/xufCQB/AQALAAIJmBGK+QBNAAAAAA==.Lordpain:BAAALgAECgcJDQAAAA==.Lortherti:BAAALgADCgUJBgAAAA==.Lorwin:BAABLgAECn8UAAIBAAgJhBlPNwDWAQABAAgJhBlPNwDWAQAAAA==.Lotusbr:BAAALgADCgEJAQAAAA==.Louisenacioo:BAAALgAECgcJEwAAAA==.Loátrak:BAAALgADCgMJAwAAAA==.',
Lu='Luanne:BAAALgADCgEJAQAAAA==.Luccablack:BAAALgAECgMJAwAAAA==.Lucyx:BAAALgAECgEJAQAAAA==.Luidar:BAAALgAECgQJBAAAAA==.Lukaslions:BAABLgAECn8ZAAINAAgJjA8MLAB+AQANAAgJjA8MLAB+AQAAAA==.Lunarie:BAAALgAECgYJEwABLgAECgcJBwAGAAAAAA==.Luphoe:BAABLgAECn8nAAMCAAcJ9RzHJwAWAgACAAcJ9RzHJwAWAgAZAAQJkw58VACMAAAAAA==.Luxanä:BAAALgADCggJDQAAAA==.',
['Lé']='Léio:BAAALgADCgcJCAAAAA==.Léora:BAAALgADCgIJAgAAAA==.',
['Lø']='Lørdsith:BAAALgAECgYJCAABLgAECggJBgAGAAAAAA==.',
['Lÿ']='Lÿcäns:BAAALgADCgMJAwAAAA==.',
Ma='Maars:BAAALgAECgEJAQAAAA==.Madagalux:BAABLgAECn8gAAIMAAYJ5wdYFADtAAAMAAYJ5wdYFADtAAAAAA==.Madalenna:BAAALgADCgEJAQAAAA==.Madjack:BAAALgAECgMJAwAAAA==.Madushi:BAAALgAECgMJBAAAAA==.Magatiun:BAAALgADCgMJBAAAAA==.Magogunt:BAABLgAECn8gAAIFAAkJMxFTRgDtAQAFAAkJMxFTRgDtAQAAAA==.Maguul:BAABLgAECn8XAAIEAAgJRRUnDwCjAQAEAAgJRRUnDwCjAQAAAA==.Magzifeh:BAABLgAECn8UAAIBAAcJ3SBOLAACAgABAAcJ3SBOLAACAgAAAA==.Mahadevi:BAAALgADCgIJAgAAAA==.Malandrvs:BAAALgAFFAEJAwAAAA==.Maljamim:BAAALgADCgIJAgAAAA==.Mamuthwar:BAABLgAECn8ZAAMNAAcJnRgeNgDQAQANAAcJnRgeNgDQAQAQAAEJMQ7ZQQA1AAAAAA==.Mandingavudu:BAAALgAECgUJBgABLgAECggJEQAGAAAAAA==.Manei:BAAALgAECgMJAwAAAA==.Mangalarga:BAAALgADCgEJAQAAAA==.Manmoden:BAAALgADCgUJBQABLgAECggJEQAGAAAAAA==.Mannatur:BAAALgAECggJEQAAAA==.Manopaladino:BAAALgADCgYJBgAAAA==.Manowlo:BAAALgAECgMJAwAAAA==.Manzagon:BAAALgAECgUJCAABLgAECggJEQAGAAAAAA==.Marmelo:BAAALgADCgQJBAAAAA==.Marretasanta:BAABLgAECn8kAAIDAAcJCRRycQBrAQADAAcJCRRycQBrAQAAAA==.Marù:BAAALgAECgYJCwAAAA==.Marúh:BAACLgAFFH8RAAIHAAQJMRvTHwAxAQAHAAQJMRvTHwAxAQAuAAQKfycAAgcACAnzIsQFABYDAAcACAnzIsQFABYDAAAA.Matroná:BAAALgADCggJBwAAAA==.Maxmorf:BAAALgADCgUJBQAAAA==.Mayarabr:BAAALgAECgYJDAAAAA==.Mazeratos:BAAALgAECgMJBQAAAA==.',
Mc='Mcorelhao:BAAALgADCgEJAQAAAA==.',
Me='Medoza:BAAALgAECgQJBgAAAA==.Megrezz:BAAALgAECgEJAQAAAA==.Mehiel:BAAALgAECgEJAQAAAA==.Mekihlvshtak:BAAALgAECgEJAQAAAA==.Meliøðas:BAAALgADCgEJAQAAAA==.Mendingu:BAAALgAECggJEQAAAA==.Mercenarybr:BAAALgAECgEJAgAAAA==.Merumim:BAAALgAECgYJCwAAAA==.Metalgirl:BAAALgADCgYJCwAAAA==.Methamorfo:BAAALgADCgcJBwAAAA==.',
Mi='Midrão:BAAALgAECggJEwAAAA==.Miisuky:BAAALgADCgUJBAAAAA==.Mikasaackerr:BAAALgAECgEJAgAAAA==.Milczarek:BAAALgAECgEJAgAAAA==.Mindlocker:BAABLgAECn8XAAILAAYJ8gZbqgDWAAALAAYJ8gZbqgDWAAAAAA==.Minorus:BAAALgAECgcJEgAAAA==.Mistifs:BAABLgAECn8ZAAIfAAgJGxmvFQAwAgAfAAgJGxmvFQAwAgAAAA==.',
Mo='Modogz:BAAALgADCgYJBgAAAA==.Momongadk:BAAALgADCgcJBwAAAA==.Monkeydking:BAAALgADCgUJBQAAAA==.Morania:BAABLgAECn8XAAIKAAgJUwbJEgDwAAAKAAgJUwbJEgDwAAAAAA==.Mordekais:BAAALgAECgIJAgAAAA==.Morganne:BAAALgAECgEJAQAAAA==.Morinami:BAAALgADCgUJBQAAAA==.Moriyama:BAABLgAECn8kAAICAAcJuBsrJQABAgACAAcJuBsrJQABAgAAAA==.Morphisz:BAAALgAECgcJCgABLgAECggJEQAGAAAAAA==.Morphiszs:BAAALgAECgMJBAABLgAECggJEQAGAAAAAA==.Morphizs:BAAALgAECgEJAgABLgAECggJEQAGAAAAAA==.Mortesan:BAAALgAECgEJAQABLgAECgUJCgAGAAAAAA==.',
Mp='Mpastor:BAAALgADCgUJBQAAAA==.',
Mu='Muca:BAAALgADCgEJAQAAAA==.Muho:BAAALgADCgEJAQAAAA==.Mukonha:BAABLgAECn8jAAILAAcJeA7cdgA2AQALAAcJeA7cdgA2AQAAAA==.',
['Mã']='Mãoleves:BAAALgADCgEJAQAAAA==.',
['Må']='Måximus:BAAALgAECgMJBAAAAA==.',
['Mü']='Müller:BAAALgADCgEJAQABLgAECgcJDwAGAAAAAA==.',
Na='Naeryndam:BAAALgADCgEJAQAAAA==.Namyara:BAAALgAECgEJAQAAAA==.Narutowow:BAAALgADCgMJAwAAAA==.Natcmd:BAAALgADCggJEAAAAA==.Navira:BAAALgAECgEJAQAAAA==.Nayanna:BAAALgADCgcJDQAAAA==.',
Ne='Negblack:BAAALgAFFAEJAgAAAA==.Neggi:BAAALgAECgUJBwAAAA==.Nemesysy:BAAALgAECgMJAwAAAA==.Nerphien:BAAALgADCgUJBQAAAA==.Nesktpally:BAAALgAECgcJCAAAAA==.Netbrood:BAAALgADCgUJBgABLgAECgUJBwAGAAAAAA==.Netbrother:BAAALgAECgUJBwAAAA==.Nethdorai:BAAALgADCgQJBAAAAA==.Netherbane:BAABLgAECn8eAAMQAAcJWBc/EwCeAQAQAAcJWBc/EwCeAQANAAIJGQ/QhwA0AAAAAA==.Nezuko:BAAALgADCgcJEQABLgAECggJLAALAOUWAA==.',
Ni='Nightmære:BAAALgAECgQJCwAAAA==.Nikelok:BAAALgAECgYJCAAAAA==.Ninfador:BAABLgAECn8eAAIcAAYJgxdfJwBmAQAcAAYJgxdfJwBmAQAAAA==.Ninpus:BAAALgAECgMJAwAAAA==.',
No='Noobmasteer:BAAALgADCgIJAgAAAA==.Nooneknow:BAABLgAECn81AAIUAAkJVCGlDwDQAgAUAAkJVCGlDwDQAgAAAA==.Nosios:BAAALgAECgYJBgAAAA==.Nosrede:BAAALgAECgEJAQAAAA==.Notz:BAAALgADCgMJBAAAAA==.',
Nu='Nucciwarrior:BAAALgAECgUJCAAAAA==.Nuccixama:BAAALgAECgcJCQAAAA==.Nuriel:BAAALgAECgYJBQAAAA==.',
Ny='Nyde:BAAALgAECgMJAwAAAA==.',
['Nø']='Nøar:BAAALgADCgIJAgAAAA==.',
Oa='Oakshlar:BAAALgAFFAEJAQAAAA==.',
Oc='Ocelaris:BAAALgAECgEJAgAAAA==.',
Oh='Ohlu:BAAALgAECgYJCQAAAA==.Ohluh:BAAALgAECgcJDQAAAA==.',
Or='Oryana:BAAALgADCgcJIAAAAA==.Oríon:BAAALgADCgIJAgAAAA==.',
Ot='Otton:BAABLgAECn8dAAIDAAYJdweQzQDRAAADAAYJdweQzQDRAAAAAA==.',
Ov='Overnigth:BAAALgADCgIJAgAAAA==.Overwalker:BAAALgAECgEJAQAAAA==.Ovosemdente:BAAALgADCgEJAQAAAA==.',
Ow='Owllskull:BAAALgAECgYJEQAAAA==.',
Oz='Ozovo:BAAALgAECgcJDwAAAA==.',
Pa='Pacoka:BAAALgADCgQJBQAAAA==.Padrafferty:BAAALgADCgcJBwAAAA==.Paidesanto:BAAALgAECgYJEAAAAA==.Paidesantox:BAAALgAECgYJEAABLgAECgkJKwANAOcTAA==.Paladinokun:BAAALgAECgUJCgAAAA==.Palanis:BAAALgAECgcJBwAAAA==.Palazarta:BAAALgAECgcJEQAAAA==.Pandavoli:BAAALgAECgUJCQAAAA==.Panky:BAAALgAECgQJBAAAAA==.Panquecudo:BAAALgADCgIJAgAAAA==.',
Pd='Pdois:BAAALgADCgMJAwAAAA==.',
Pe='Pesscador:BAAALgAECgMJAwAAAA==.Petrolesk:BAAALgAECgYJBwAAAA==.',
Pi='Piriguetee:BAAALgADCgEJAQAAAA==.Pirro:BAAALgAECgEJAQAAAA==.Pisadinha:BAAALgADCgcJBwAAAA==.',
Pk='Pkzimn:BAAALgADCgUJBQAAAA==.',
Pl='Playsson:BAAALgAECgYJEgAAAA==.Plottwist:BAAALgADCgcJDwABLgAECgkJLgAUAMwYAA==.',
Po='Pogonus:BAAALgADCgIJAgAAAA==.Pontocego:BAAALgAECgQJBAAAAA==.Posturado:BAAALgADCgEJAQAAAA==.Powerworth:BAAALgAECgEJAQAAAA==.',
Pr='Pravios:BAAALgAECgMJBgAAAA==.Priestkill:BAAALgADCgcJCQAAAA==.Primewolf:BAAALgAECgIJAgAAAA==.',
Ps='Psicomanic:BAAALgADCgMJAwAAAA==.',
Pt='Pterodactilo:BAAALgAECgYJAQAAAA==.',
Pu='Puherito:BAAALgAECgQJCAAAAA==.Purgas:BAAALgAFFAEJAQAAAA==.',
Qu='Quinthalam:BAAALgADCgMJAwAAAA==.',
Ra='Rafac:BAAALgAECgEJAgABLgAECggJDAAGAAAAAA==.Rafazinho:BAAALgADCgQJBAAAAA==.Ramyna:BAAALgAECgMJBQAAAA==.Ramyra:BAAALgADCgcJDQAAAA==.Raphaeldh:BAAALgAECgEJAgAAAA==.Raphahunterr:BAAALgADCgEJAQAAAA==.Raposa:BAAALgADCgEJAQAAAA==.Raposinha:BAAALgADCgMJAwAAAA==.Rarkway:BAAALgAECgcJCwAAAA==.Ravenblak:BAAALgADCgEJAQAAAA==.Rayanne:BAAALgADCgYJBgAAAA==.',
Re='Reckfull:BAAALgAECgYJBgAAAA==.Regininha:BAAALgAECgEJAQAAAA==.Reloumifrend:BAAALgAECgcJCgAAAA==.Rendros:BAAALgADCgUJBQAAAA==.',
Rh='Rhaegaar:BAAALgAECgcJDQAAAA==.Rhanideri:BAAALgADCgEJAQAAAA==.Rhodinius:BAAALgAECgMJCAAAAA==.',
Ri='Rivotreel:BAAALgADCgQJBAAAAA==.',
Ro='Robeerth:BAAALgAFFAEJAQAAAA==.Rochera:BAAALgAECgEJAQAAAA==.Rokhanar:BAAALgAECgUJCAAAAA==.',
Ru='Rudemonster:BAAALgAECgEJAQAAAA==.Ruhtarr:BAAALgADCgEJAQAAAA==.',
Ry='Ryukato:BAAALgAECgQJBQAAAA==.',
Sa='Saek:BAAALgAECgcJEgAAAA==.Sanderclone:BAAALgAECgEJAQAAAA==.Sanguenafaca:BAAALgADCgYJBwAAAA==.Santiss:BAABLgAECn8WAAIDAAYJDhUSiwA5AQADAAYJDhUSiwA5AQAAAA==.Santorini:BAAALgAECgcJDQAAAA==.Saphirot:BAAALgADCgUJBQAAAA==.Saphis:BAAALgADCgEJAQAAAA==.Sardado:BAAALgAECgEJAQAAAA==.Sardron:BAAALgADCgMJAwAAAA==.',
Sc='Scanorr:BAAALgAECgYJDAAAAA==.Scheffers:BAAALgAECgYJCwAAAA==.',
Se='Selah:BAAALgADCgMJBQAAAA==.Selver:BAAALgAECgcJCAABLgAFFAcJGgAgALAaAA==.Selüne:BAAALgAECgcJDQAAAA==.Sephora:BAAALgAECgYJCwABLgAECggJKQAVAFwXAA==.Sevagoth:BAAALgAECgEJAQAAAA==.',
Sh='Shadowlock:BAAALgADCgIJAQABLgAECgYJDgAGAAAAAA==.Shadowmornac:BAAALgAECgMJBAAAAA==.Shamanica:BAAALgAECgEJAgAAAA==.Shamateus:BAAALgADCggJEwAAAA==.Shasuna:BAAALgADCgIJAgAAAA==.Shaunnun:BAAALgADCgEJAQAAAA==.Shenloong:BAAALgADCgYJBgAAAA==.Shinnók:BAAALgAECgIJAgAAAA==.Shiíro:BAAALgAFFAIJAwABLgAFFAQJEQADABAkAA==.Shynato:BAAALgADCgEJAQAAAA==.Shynock:BAAALgADCgEJAQAAAA==.Shyzuno:BAAALgADCgQJBAAAAA==.Shãka:BAAALgADCgMJAwAAAA==.',
Si='Siladriel:BAAALgADCgMJAwAAAA==.Sirgonzo:BAABLgAECn8UAAIDAAgJZxfuRwDPAQADAAgJZxfuRwDPAQAAAA==.',
Sk='Skullexus:BAAALgAECgMJBAAAAA==.Skunkbr:BAAALgADCgEJAQAAAA==.',
Sl='Sleepychety:BAAALgAECgUJBgAAAA==.Slowsmoke:BAAALgADCgYJBwAAAA==.Slyfer:BAAALgAECgQJBAAAAA==.',
Sn='Snatzz:BAAALgADCgMJAgAAAA==.',
So='Soggoth:BAAALgADCgkJCQAAAA==.Solk:BAAALgAECgMJBAAAAA==.Sontarfury:BAAALgAECgEJAQAAAA==.Sorim:BAABLgAECn8dAAICAAYJYB9wJQD/AQACAAYJYB9wJQD/AQAAAA==.Soryan:BAABLgAECn8hAAICAAcJ4RRuNgCdAQACAAcJ4RRuNgCdAQAAAA==.Soulassassin:BAAALgADCgIJAwAAAA==.Soulhell:BAABLgAECn8cAAIcAAYJaxREKgBTAQAcAAYJaxREKgBTAQAAAA==.',
Sp='Spartanlofs:BAAALgADCgcJEQAAAA==.Spawndeath:BAAALgADCgEJAQAAAA==.',
Ss='Ssushii:BAAALgAECgEJAQAAAA==.',
St='Staffkiller:BAAALgAECgEJAQAAAA==.Stigmata:BAAALgADCgcJCAAAAA==.Stixlightmix:BAABLgAFFH8FAAMXAAMJ5hEWIQCaAAAXAAIJORgWIQCaAAAlAAEJQAVUTwA6AAAAAA==.Stixmixdk:BAAALgAFFAQJBAAAAA==.Stixmixwarr:BAAALgAFFAYJAQAAAA==.Straz:BAAALgADCgQJBAAAAA==.Strongman:BAAALgAECgYJBgAAAA==.Stx:BAAALgAECgUJBQAAAA==.',
Su='Subsdk:BAACLgAFFH8SAAIUAAUJGRDAUAArAQAUAAUJGRDAUAArAQAuAAQKfyIAAhQACAm3HFpAAOABABQACAm3HFpAAOABAAAA.Sunwalkers:BAAALgAECgUJBgAAAA==.Supfurry:BAAALgADCgcJBwAAAA==.',
Sw='Swam:BAAALgADCgkJCQAAAA==.',
Sy='Systeni:BAAALgADCgkJCwAAAA==.',
['Sø']='Søøssø:BAAALgAECgQJBAAAAA==.',
Ta='Taha:BAAALgAECgYJDgAAAA==.Taillys:BAAALgADCgMJBAAAAA==.Tainy:BAAALgAECgEJAQAAAA==.Takenaka:BAAALgADCgMJAwAAAA==.Tarez:BAAALgAECgkJCwAAAA==.Tarfonir:BAAALgAECgYJCQAAAA==.Tavalira:BAAALgADCgYJBgAAAA==.',
Te='Tealen:BAAALgAECgEJAQAAAA==.Ted:BAAALgAECgcJDAAAAA==.Teiseken:BAAALgAECgcJBwAAAA==.Tempesfúria:BAAALgADCgIJAgAAAA==.Tenébria:BAAALgAECgcJBwAAAA==.Teratsemknk:BAAALgAECgUJBQAAAA==.',
Th='Tharnforge:BAAALgAECgEJAQAAAA==.Thejokker:BAABLgAFFH8GAAINAAMJgQDROQBoAAANAAMJgQDROQBoAAAAAA==.Thelaststorm:BAAALgAECgkJAwAAAA==.Themooster:BAAALgAFFAEJAgAAAA==.Thepickles:BAAALgADCgkJGwAAAA==.Thepunk:BAAALgAECgQJEQAAAA==.Thesindorei:BAAALgAECgEJAQAAAA==.Thintor:BAAALgADCgEJAQAAAA==.Thormento:BAABLgAECn8VAAIHAAcJkBH8SQBTAQAHAAcJkBH8SQBTAQAAAA==.Thraell:BAAALgAECgEJAQAAAA==.',
Ti='Tigerblood:BAAALgADCgUJBQAAAA==.Tipooreeii:BAAALgADCgEJAQAAAA==.Titanicos:BAAALgAECgYJBQAAAA==.',
Tj='Tjhunter:BAABLgAECn8fAAIBAAgJnQpeSQCNAQABAAgJnQpeSQCNAQAAAA==.',
To='Tobbiy:BAAALgAFFAIJBAAAAA==.Toddyb:BAAALgAECggJCwAAAA==.Tonytornado:BAAALgAECgEJAQAAAA==.',
Tr='Tranh:BAAALgADCgkJFQAAAA==.Traxer:BAAALgADCgQJBAAAAA==.Tripäsecä:BAAALgAECgYJCwAAAA==.Troladora:BAABLgAECn8VAAIFAAYJqA4iqAATAQAFAAYJqA4iqAATAQAAAA==.Trévor:BAAALgAECgEJAQAAAA==.',
Ts='Tsreis:BAAALgADCgEJAQAAAA==.',
Tw='Twoheavy:BAAALgADCgkJCQABLgAECgYJCQAGAAAAAA==.',
Ty='Tyrandrisa:BAAALgADCgIJAQAAAA==.',
['Tá']='Tátu:BAAALgADCgMJAwAAAA==.',
Um='Ummetrodefio:BAAALgADCgEJAQAAAA==.',
Ut='Uthred:BAABLgAECn8rAAQUAAkJHQeNgwA3AQAUAAkJcwSNgwA3AQAiAAYJoARvDADrAAAeAAMJrgkQPgBnAAAAAA==.',
Va='Vaelryn:BAAALgAECgUJBwABLgAECgYJBgAGAAAAAA==.Valdemmon:BAAALgAECgQJBgAAAA==.Valororo:BAAALgAECgYJEgAAAA==.Vandlesh:BAAALgAECgYJDwAAAA==.Vardha:BAAALgADCgQJBAAAAA==.Varka:BAAALgADCgYJGQAAAA==.',
Ve='Velkharun:BAAALgAECgQJCwABLgAFFAEJAQAGAAAAAA==.Venatrin:BAAALgADCgkJCQAAAA==.Vess:BAAALgAECgQJBAAAAA==.Vexxv:BAABLgAECn8UAAIUAAUJshqnigBrAQAUAAUJshqnigBrAQAAAA==.Vexxz:BAAALgAECgYJBwAAAA==.',
Vi='Viquue:BAAALgADCgYJBgAAAA==.Vivisoft:BAAALgADCgMJAwAAAA==.',
Vo='Voidrb:BAAALgADCgcJBwABLgAECggJEQAGAAAAAA==.Vovogamer:BAAALgAECgQJBAAAAA==.',
['Vò']='Vòxs:BAACLgAFFH8QAAMQAAQJcxB9GQDPAAAQAAMJ8xJ9GQDPAAANAAIJug+1MgCVAAAuAAQKf0sAAxAACAk8JLYDAMQCABAABwnDJLYDAMQCAA0ABglHHoQuAPcBAAAA.',
Wa='Walkery:BAAALgADCgIJAgAAAA==.Wattari:BAABLgAECn8ZAAIPAAYJDgStMQCPAAAPAAYJDgStMQCPAAAAAA==.',
Wh='Whiteep:BAAALgADCgYJCAAAAA==.Whiteseraph:BAAALgADCgEJAQAAAA==.Whynchester:BAAALgADCgEJAQAAAA==.',
Wi='Wiilami:BAAALgADCgMJAwAAAA==.Windsailor:BAAALgAECgUJBQAAAA==.Wiserys:BAABLgAECn8lAAMLAAYJjiBLQADDAQALAAYJjiBLQADDAQAMAAMJOQyiGwCXAAAAAA==.',
Wm='Wmarcão:BAAALgAECgYJEQAAAA==.',
Wo='Wolfiez:BAAALgAECgUJDAAAAA==.Wolfnwar:BAAALgAECgQJDAAAAA==.Wopz:BAAALgADCgUJBQAAAA==.Worq:BAAALgADCgYJBgAAAA==.',
Wq='Wqz:BAABLgAECn8VAAIBAAcJWhmTNgDUAQABAAcJWhmTNgDUAQAAAA==.',
Wu='Wunamuno:BAAALgADCgkJCQAAAA==.',
Xa='Xallatath:BAAALgADCgUJBQAAAA==.Xamela:BAAALgADCgMJAwAAAA==.Xamãna:BAAALgAECgQJCQAAAA==.',
Xe='Xevron:BAAALgAECgQJBAAAAA==.Xexnetw:BAAALgAECgQJBwAAAA==.Xexnew:BAABLgAECn8ZAAMeAAkJ9BqoCwAkAgAeAAkJ9BqoCwAkAgAUAAEJaQe0SwEnAAAAAA==.',
Xi='Xidevill:BAAALgAECgIJCAAAAA==.Xinthorak:BAAALgADCgEJAgAAAA==.Xinzhou:BAAALgADCgQJCAAAAA==.Xiseth:BAAALgAECgIJAgAAAA==.Xixíca:BAAALgADCgUJBgAAAA==.',
Xm='Xmari:BAAALgAECgYJBwAAAA==.',
Xn='Xnyx:BAAALgADCgYJBgAAAA==.',
Xu='Xulaman:BAAALgAECgcJDgAAAA==.Xungodz:BAAALgADCgQJBAAAAA==.Xunxu:BAABLgAECn8ZAAMDAAYJdhMQhwBsAQADAAYJdhMQhwBsAQAjAAEJJgM2ngArAAAAAA==.',
Xy='Xynrath:BAAALgADCgMJAwAAAA==.',
['Xÿ']='Xÿon:BAAALgAECgEJAQAAAA==.',
Ya='Yamëte:BAAALgADCgEJAQAAAA==.Yannadcg:BAACLgAFFH8FAAIVAAMJtwNEHQChAAAVAAMJtwNEHQChAAAuAAQKfy4AAhUACQmRCzQiAI4BABUACQmRCzQiAI4BAAAA.',
Yo='Yorickundyer:BAAALgAECgIJAwAAAA==.Youdie:BAABLgAECn8YAAIgAAgJhRLwKgCEAQAgAAgJhRLwKgCEAQAAAA==.',
Yu='Yulthuan:BAAALgADCgMJAwAAAA==.',
Yv='Yvernus:BAAALgAECgQJBgAAAA==.',
Yz='Yziepala:BAAALgAECgMJBAAAAA==.',
Za='Zaaraki:BAABLgAECn8uAAMUAAkJzBjzRgDKAQAUAAkJdRfzRgDKAQAeAAcJVRYFHABJAQAAAA==.Zarolho:BAABLgAECn8VAAIIAAYJSA6EUAAFAQAIAAYJSA6EUAAFAQAAAA==.',
Ze='Zenitsua:BAAALgAECgYJCQAAAA==.Zenzeluk:BAAALgAECgMJAwAAAA==.Zephiir:BAABLgAECn8UAAIDAAYJ9RQ0iQA9AQADAAYJ9RQ0iQA9AQAAAA==.Zeroxyz:BAAALgADCgYJBgABLgAECgYJEwAGAAAAAA==.Zeryen:BAAALgAECgEJAQAAAA==.',
Zh='Zhunka:BAAALgADCgEJAgAAAA==.',
Zo='Zornak:BAAALgADCgUJBQAAAA==.',
Zz='Zzx:BAAALgADCgcJBwAAAA==.',
['Zé']='Zécasete:BAAALgADCgUJBwAAAA==.',
['Ál']='Álucard:BAAALgAECgcJEwAAAA==.',
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
