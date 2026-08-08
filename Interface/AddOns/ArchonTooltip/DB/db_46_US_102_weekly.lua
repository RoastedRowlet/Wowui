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

local lookup = {'Hunter-BeastMastery','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Priest-Discipline','Warrior-Protection','Warrior-Fury','Druid-Restoration','Druid-Balance','Druid-Feral','Unknown-Unknown','Paladin-Protection','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warlock-Destruction','Warlock-Demonology','DeathKnight-Unholy','Warlock-Affliction','Druid-Guardian','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Mage-Arcane','Priest-Holy','DemonHunter-Devourer','Monk-Windwalker','DemonHunter-Vengeance','Hunter-Marksmanship','Priest-Shadow','Mage-Fire','Monk-Mistweaver','DemonHunter-Havoc','Monk-Brewmaster',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abortheira:BAAALgADCgUJBQAAAA==.',
Ac='Acelord:BAACLgAFFH8IAAIBAAMJlQ3LOADDAAABAAMJlQ3LOADDAAAuAAQKfyMAAgEACQlvGMUlAEsCAAEACQlvGMUlAEsCAAAA.Actaeon:BAAALgAECgQJBgAAAA==.',
Ad='Adaar:BAAALgAECgEJAQAAAA==.Adadebox:BAABLgAECn8ZAAMCAAYJXh9FHQAZAgACAAYJXh9FHQAZAgADAAEJhghzbQAfAAAAAA==.Adakat:BAAALgADCgEJAQAAAA==.Adanthedark:BAAALgADCgIJAgAAAA==.Adariom:BAAALgADCgUJCAAAAA==.Adilma:BAAALgAECgYJDAAAAA==.Adrian:BAAALgADCgEJAQAAAA==.Adriannos:BAAALgAECgEJAQAAAA==.',
Ae='Aethir:BAAALgADCgYJBwAAAA==.',
Ag='Agakii:BAAALgADCgEJAQAAAA==.Aghatta:BAAALgAECgcJBwAAAA==.Agonyy:BAAALgAECgUJEAAAAA==.Agrias:BAAALgAECgEJAgAAAA==.',
Ah='Aharadack:BAAALgAECgIJAgAAAA==.',
Ak='Akawaka:BAAALgAECgEJAQAAAA==.Akiji:BAAALgAECgIJBgAAAA==.Akimurad:BAAALgAECgYJBwAAAA==.',
Al='Alakazam:BAAALgADCgcJBwAAAA==.Alanie:BAAALgADCggJCAABLgAFFAIJBgAEAOkPAA==.Ald:BAAALgAECgEJAgAAAA==.Aldebaraum:BAAALgAECgcJDQAAAA==.Alexextreme:BAABLgAECn8WAAIBAAcJ8gYDqADyAAABAAcJ8gYDqADyAAAAAA==.Aliaksandr:BAAALgAECgEJAQAAAA==.Alikth:BAAALgADCgYJBgAAAA==.Alista:BAAALgAECgQJAwAAAA==.Allandyr:BAACLgAFFH8hAAIBAAQJphYRHwAsAQABAAQJphYRHwAsAQAuAAQKf3MAAgEACQm9HzQDALkCAAEACQm9HzQDALkCAAAA.Alvarao:BAAALgAECgQJBAAAAA==.',
Am='Amandadark:BAAALgAECgEJAgAAAA==.Amano:BAAALgADCgYJDAAAAA==.',
An='Anamagab:BAAALgAECgUJBwABLgAECggJKgAFAF0XAA==.Anamia:BAAALgAECgEJAgABLgAFFAIJBgAEAOkPAA==.Anaxthacia:BAAALgADCgMJAwAAAA==.Andarilho:BAAALgAECgYJBwAAAA==.Andinth:BAAALgAECgIJAgAAAA==.Andrepvp:BAAALgADCggJDwAAAA==.Anelie:BAABLgAFFH8GAAQEAAIJ6Q9tHgBPAAAEAAEJbRdtHgBPAAAGAAIJUwH6GwBHAAAHAAEJZQjhNwA+AAAAAA==.Anellÿ:BAAALgAECgIJAwAAAA==.Angelloz:BAABLgAECn8rAAIDAAgJARK0fAB1AQADAAgJARK0fAB1AQAAAA==.Anjelvs:BAAALgAECgYJBgAAAA==.Anksunamoon:BAACLgAFFH8HAAIIAAUJoweLMQDpAAAIAAUJoweLMQDpAAAuAAQKfyMABAgACQnfE65AAI8BAAgACAl7Ea5AAI8BAAkABgm4Dhk3ADkBAAoAAgk+EFY8AGgAAAAA.Annaoh:BAABLgAECn8cAAIDAAgJVB3RQQABAgADAAgJVB3RQQABAgAAAA==.Annedin:BAAALgAECgEJBAABLgAECgUJBgALAAAAAA==.Annia:BAAALgAECgIJAgAAAA==.Anyid:BAAALgAECgQJCgAAAA==.Anãodengoso:BAABLgAECn8pAAMDAAgJSCZgFQDpAgADAAgJSCZgFQDpAgAMAAIJIxLBPQBmAAABLgAECggJKQADAEgmAA==.',
Ap='Apökalÿpsïs:BAACLgAFFH8MAAINAAMJ+REJOgDbAAANAAMJ+REJOgDbAAAuAAQKfzIAAg0ACQnPG5AdAKsCAA0ACQnPG5AdAKsCAAAA.',
Aq='Aquadel:BAAALgAECgUJAwAAAA==.',
Ar='Arator:BAAALgAECggJDwAAAA==.Ardry:BAAALgADCgYJBgAAAA==.Argaloth:BAAALgAECgYJBwAAAA==.Argonzinha:BAAALgAECgEJAQAAAA==.Artemisfowl:BAAALgAECgcJCgAAAA==.',
As='Asaff:BAAALgADCgMJAwAAAA==.Asassincego:BAAALgADCgIJAgAAAA==.Ashryel:BAAALgAECgEJAQAAAA==.Ashthon:BAABLgAECn8eAAIBAAcJgxxINgDVAQABAAcJgxxINgDVAQAAAA==.Ashyashiida:BAAALgADCgQJBQAAAA==.Asmitta:BAAALgADCgQJBAAAAA==.Astterix:BAAALgADCgIJAgAAAA==.',
At='Atalantha:BAAALgAECgIJAgAAAA==.Athelass:BAAALgAECgEJAQAAAA==.Atomicdk:BAAALgAECgUJCgAAAA==.Atomictank:BAAALgAECgcJEwAAAA==.Atonos:BAAALgAECgcJDgAAAA==.',
Au='Auquenai:BAAALgADCgUJBQAAAA==.Aurielis:BAAALgAECgEJAgAAAA==.',
Av='Averagemage:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAAALgAECgQJBAAAAA==.',
Az='Azadium:BAAALgAECgUJCgAAAA==.Azul:BAAALgAECgUJCwAAAA==.',
['Aë']='Aëma:BAAALgAECgUJBQAAAA==.',
Ba='Baala:BAAALgAECgEJAgAAAA==.Babalysaga:BAAALgAECgUJBwAAAA==.Badayaga:BAAALgADCgIJAgAAAA==.Bahoz:BAAALgAECgUJBQABLgAECgYJDQALAAAAAA==.Bakunogrind:BAAALgAECgUJBQABLgAFFAQJBwAOAEMeAA==.Balragouldur:BAAALgAECgQJBgAAAA==.Balthar:BAACLgAFFH8HAAQOAAIJqAV8bgBgAAAOAAIJqAV8bgBgAAAPAAIJfwI9UQBRAAAQAAEJ5gJuHQA3AAAuAAQKfyAABA8ABwk6Ek9KAAsBAA8ABwmjEU9KAAsBABAABAkKEWsdAPUAAA4ABAkGD26qAHQAAAAA.Barathrum:BAAALgAECgEJAQAAAA==.Barcaldas:BAAALgAECgUJBgAAAA==.Barrocø:BAAALgAECgQJBQABLgAECggJGAAEAAIcAA==.Basara:BAAALgAECgcJEgAAAA==.Batefraco:BAAALgADCgIJAgAAAA==.',
Bb='Bbiel:BAABLgAECn8nAAMRAAYJnRMAFAAQAQARAAYJnRMAFAAQAQASAAQJwQZl7QCFAAAAAA==.',
Be='Beatriz:BAAALgAFFAEJAQAAAA==.Beelgarath:BAAALgAECgYJDgAAAA==.Beherit:BAAALgAECgMJBgAAAA==.Beledrel:BAAALgAECgEJAgAAAA==.Beliall:BAAALgAECgQJBwAAAA==.Belowlight:BAAALgAECgYJEAAAAA==.Belttazar:BAAALgADCgkJDwAAAA==.Bemmaith:BAAALgAECgQJBAAAAA==.Benoboi:BAAALgAECgMJAwAAAA==.Benzema:BAAALgADCgMJAgABLgAECgkJGwATABwQAA==.Berwin:BAAALgAECgMJBAAAAA==.Berzan:BAAALgAECgUJCwAAAA==.Beyoond:BAACLgAFFH8hAAQSAAYJeBSuKgDiAAASAAQJthOuKgDiAAAUAAIJgBdUIQBPAAARAAEJ+wcYJwBHAAAuAAQKfzwABBIACQm+HGElAEkCABIACQm/G2ElAEkCABEABAm3D+cxAPEAABQAAwnBFrsfAMMAAAAA.',
Bh='Bhalin:BAAALgAECgUJCQABLgAFFAMJBgADABkhAA==.',
Bi='Bielinski:BAAALgAECgQJBAAAAA==.Biinarc:BAAALgAECgEJAQAAAA==.',
Bl='Blackdut:BAACLgAFFH8OAAISAAMJBgY2QACXAAASAAMJBgY2QACXAAAuAAQKfxUAAxIABwmyEWtuAF8BABIABwl5EWtuAF8BABEABAkpCtYlAIYAAAAA.Blackfear:BAABLgAFFH8IAAMVAAQJcA3LFAB/AAAVAAMJxAzLFAB/AAAJAAIJvQs9IABzAAABLgAFFAQJEAABAIcVAA==.Blackrøse:BAAALgADCgYJBgAAAA==.Blackteriaa:BAABLgAECn8UAAINAAYJ/RNCmgBFAQANAAYJ/RNCmgBFAQAAAA==.Blacrapumzel:BAAALgAECgMJAwAAAA==.Blakwolf:BAABLgAECn8aAAIHAAcJLw/MCgAUAQAHAAcJLw/MCgAUAQAAAA==.Blankis:BAAALgADCgYJCQAAAA==.Blastoize:BAAALgAECgQJCAAAAA==.Blizther:BAAALgADCgIJAgAAAA==.Bloodh:BAAALgAECgUJCQAAAA==.Bloodyz:BAAALgAECgMJBAAAAA==.Bls:BAAALgADCgMJAwAAAA==.',
Bo='Boijf:BAAALgADCgEJAQAAAA==.Boladomal:BAAALgAECgQJBQAAAA==.Bolt:BAAALgADCgcJBwAAAA==.Bones:BAAALgAECgEJAQAAAA==.Borisobruxo:BAAALgAECgEJAQAAAA==.Boromy:BAAALgAECgcJDQAAAA==.Boruck:BAAALgAECgIJAwAAAA==.',
Br='Braandom:BAAALgAECgcJEAAAAA==.Bradan:BAABLgAECn8eAAIHAAgJURWcKgAOAgAHAAgJURWcKgAOAgAAAA==.Braeon:BAAALgAECgMJAwAAAA==.Brandomm:BAAALgAECgYJDwAAAA==.Branmir:BAAALgAECgMJBgAAAA==.Brazilerinha:BAAALgAECgUJBwAAAA==.Brewtide:BAAALgADCgEJAQAAAA==.Bridda:BAAALgAECggJEAAAAA==.Brinkst:BAABLgAFFH8NAAIDAAMJHCJYGQAwAQADAAMJHCJYGQAwAQAAAA==.Brolho:BAAALgADCgEJAQAAAA==.Brusque:BAAALgAECgcJCgAAAA==.Bruzapaladin:BAAALgADCgUJBQAAAA==.',
Bt='Btrcaotics:BAAALgAECgIJCAAAAA==.Btrguard:BAAALgAECgIJAgAAAA==.',
Bu='Buddinha:BAAALgAECgQJBwAAAA==.Buddyxa:BAAALgAECgEJAQAAAA==.Bullkiller:BAAALgAECgEJAQAAAA==.',
['Bé']='Béto:BAACLgAFFH8IAAIOAAIJXSawHgDaAAAOAAIJXSawHgDaAAAuAAQKfxYAAg4ACQlfHRgMAPoCAA4ACQlfHRgMAPoCAAAA.',
['Bí']='Bíbs:BAABLgAECn8VAAIBAAgJkRPtVgCfAQABAAgJkRPtVgCfAQAAAA==.',
Ca='Cabanagé:BAAALgAECgUJBwAAAA==.Cabeludometa:BAAALgAECgYJDAAAAA==.Cabodecobre:BAAALgAECgUJCwAAAA==.Cainmarko:BAAALgAECgYJEAAAAA==.Caiowisk:BAABLgAECn8eAAMSAAgJNgonjQAgAQASAAgJSQcnjQAgAQARAAMJZxA5LQBjAAAAAA==.Calir:BAAALgADCgYJFgAAAA==.Calçadora:BAACLgAFFH8GAAIWAAIJYxXDKACSAAAWAAIJYxXDKACSAAAuAAQKf0EAAhYACQmqIbcFAMoCABYACQmqIbcFAMoCAAAA.Caquinha:BAAALgAECgEJAQAAAA==.Cardrok:BAAALgADCgEJAQAAAA==.Caridosa:BAAALgADCgUJBQAAAA==.Carnius:BAACLgAFFH8RAAMGAAMJIhjHDwCyAAAGAAMJIhjHDwCyAAAEAAEJDAWASAAzAAAuAAQKf0QABAYACAlHHmYRANQBAAYACAkhHWYRANQBAAcAAgm6IA6UAEoAAAQAAQkPHPduAEMAAAAA.Cartøønyz:BAAALgAECgQJBAAAAA==.Casipala:BAAALgAECgIJAgAAAA==.Casuall:BAAALgAECgcJBwAAAA==.Cataclysm:BAAALgAECgMJBAAAAA==.Catalango:BAAALgAECgUJDwAAAA==.Catapas:BAAALgAECgEJAQAAAA==.Catapita:BAAALgAECgIJAgAAAA==.Catapó:BAABLgAECn8UAAMSAAgJcxZocgBVAQASAAgJcxZocgBVAQARAAEJjQziQgAoAAAAAA==.Catapózão:BAABLgAECn8zAAIIAAkJniDHBgBLAwAIAAkJniDHBgBLAwAAAA==.Catü:BAAALgAECgEJAQAAAA==.Cavernus:BAAALgADCgMJAwAAAA==.Caves:BAAALgADCgIJAgAAAA==.Caveston:BAAALgADCgUJCgAAAA==.',
Cb='Cbestabr:BAAALgADCgYJBgAAAA==.',
Ch='Chamadmordor:BAAALgAECgMJBQAAAA==.Charats:BAAALgADCgYJDQAAAA==.Charterine:BAAALgAECgQJBAAAAA==.Chaya:BAAALgADCgUJBQAAAA==.Chicknorris:BAAALgADCgUJBQAAAA==.Chifrudaxl:BAAALgAECgMJAwAAAA==.Chrisjks:BAAALgADCgYJCgAAAA==.Chupatoba:BAAALgAECgQJBQAAAA==.',
Ci='Cindyn:BAAALgAECgEJAQAAAA==.',
Cl='Clared:BAAALgADCgEJAQAAAA==.Clarkcrente:BAAALgADCgYJBgABLgAECgMJAwALAAAAAA==.Clebeya:BAAALgADCgQJBAAAAA==.Clebsona:BAAALgAECgIJAgAAAA==.Climps:BAABLgAECn8XAAIBAAgJVxlwPQDrAQABAAgJVxlwPQDrAQAAAA==.',
Co='Cobyx:BAAALgADCgcJDAAAAA==.Cocaferoz:BAAALgADCgEJAQAAAA==.Coffeeaddict:BAAALgADCgMJAwAAAA==.Colugo:BAAALgAECgUJCgAAAA==.Coriisco:BAAALgADCgIJAgAAAA==.Corollaxei:BAABLgAECn83AAQXAAkJsxf1CwAYAgAXAAkJsxf1CwAYAgAYAAYJsQnrSAAHAQAZAAEJWAw2JgAyAAAAAA==.Corvean:BAAALgAECgEJAQAAAA==.Cosculluela:BAAALgADCgUJBwAAAA==.Cosmuh:BAAALgAECgUJBQAAAA==.Cotori:BAAALgAECgEJAQAAAA==.',
Cr='Crauwlinhu:BAAALgAECgMJBgAAAA==.Cretaceous:BAAALgADCgEJAQAAAA==.Creuzapriest:BAAALgAECgEJAQAAAA==.Cristïe:BAAALgAECgUJBQAAAA==.Crookedyoung:BAAALgAECgEJAwABLgAECgcJEAALAAAAAA==.Cruzade:BAABLgAECn8ZAAMMAAkJHxHCIwD3AAAMAAgJPhDCIwD3AAADAAcJJRGpNgBuAAABLgAFFAQJEAABAIcVAA==.Cröwllëy:BAACLgAFFH8KAAMTAAMJ5w7EqADLAAATAAMJiw3EqADLAAAaAAEJFB5pGABVAAAuAAQKfyYAAhMACAmoGBpFAPMBABMACAmoGBpFAPMBAAAA.',
Cu='Cubatao:BAABLgAECn8UAAIBAAYJUxTshwAuAQABAAYJUxTshwAuAQAAAA==.Cucaracha:BAABLgAECn8YAAISAAYJVBaYcABZAQASAAYJVBaYcABZAQAAAA==.',
['Cä']='Cärtrz:BAAALgAECgQJBAAAAA==.',
Da='Dahaka:BAAALgADCgEJAQAAAA==.Dahhak:BAAALgAECgUJCwAAAA==.Dakhgagul:BAAALgADCgUJBQAAAA==.Dakshayani:BAAALgAECgQJBQAAAA==.Dalaigalds:BAAALgAECgEJAQAAAA==.Danielbrz:BAAALgAECgUJBwAAAA==.Daniellpvp:BAAALgADCgEJAQAAAA==.Danygatuxa:BAAALgAECgUJDQAAAA==.Dardano:BAAALgAECgIJAgAAAA==.Daree:BAAALgAECgEJAQAAAA==.Darkenes:BAAALgAECgEJAQAAAA==.Darkinmt:BAAALgADCgcJCAAAAA==.Darknesstk:BAAALgAECgYJEAAAAA==.Darkowllskul:BAAALgAECgQJCAABLgAECgYJEgALAAAAAA==.Darksiderptc:BAAALgADCgcJDwAAAA==.Darthmansur:BAAALgAFFAIJBAAAAA==.Dasmithy:BAAALgAECgEJAQAAAA==.',
De='Deadvi:BAABLgAECn8YAAIbAAgJXh02DQA7AgAbAAgJXh02DQA7AgAAAA==.Deadziin:BAACLgAFFH8NAAIcAAMJ5glxFwDDAAAcAAMJ5glxFwDDAAAuAAQKfx8AAxwACAlIC18vACQBABwABwnoDF8vACQBAB0ABwlMA4gXALsAAAAA.Deathbringër:BAAALgAECgEJAgAAAA==.Deathdahaka:BAAALgAECgEJAQAAAA==.Deathheav:BAAALgADCgQJBAAAAA==.Deathivy:BAAALgAECgQJBgAAAA==.Deathmäsk:BAAALgADCgcJBwAAAA==.Defensivepls:BAAALgAECgYJBQAAAA==.Demetrix:BAAALgADCgkJCgAAAA==.Demonphantom:BAAALgAECgcJDAAAAA==.Dennyam:BAAALgAECgYJCQAAAA==.Derothey:BAABLgAECn8sAAMNAAkJXhg7WgDPAQANAAgJYBY7WgDPAQAeAAMJaRokBADvAAAAAA==.Deservis:BAAALgADCgYJBgAAAA==.Deulorem:BAACLgAFFH8PAAIfAAQJih5BEABRAQAfAAQJih5BEABRAQAuAAQKfz0AAh8ACQmBIxMCAIsDAB8ACQmBIxMCAIsDAAAA.Devilblade:BAABLgAECn8RAAIgAAgJXgmljwACAQAgAAgJXgmljwACAQAAAA==.',
Di='Diabolynn:BAAALgAECgcJEwAAAA==.Digipatrocin:BAAALgAECgUJBQAAAA==.Dimeros:BAAALgAECgcJDwAAAA==.Divinastetas:BAAALgADCgQJBAAAAA==.',
Dk='Dkatraia:BAAALgAECgMJBQAAAA==.',
Dn='Dngfafinir:BAAALgAFFAIJAgABLgAFFAUJDAADAFgXAA==.Dnghidan:BAACLgAFFH8MAAIDAAUJWBe2RAAiAQADAAUJWBe2RAAiAQAuAAQKfygAAgMACQmrHvohAKICAAMACQmrHvohAKICAAAA.Dngpain:BAAALgAECgcJEQABLgAFFAUJDAADAFgXAA==.Dngtobi:BAAALgAECgUJCQABLgAFFAUJDAADAFgXAA==.',
Do='Dollynhø:BAABLgAECn8nAAIhAAkJFSCDBgDjAgAhAAkJFSCDBgDjAgAAAA==.Donyed:BAAALgAECgUJDAAAAA==.Doomsman:BAAALgADCgUJBQAAAA==.Dottado:BAAALgADCgcJCgAAAA==.',
Dr='Drackah:BAAALgADCgcJBwAAAA==.Dracomamante:BAAALgAECgEJAQAAAA==.Draconían:BAAALgAECgEJBwAAAA==.Dracón:BAABLgAECn8VAAIZAAkJ/gsmAgAwAQAZAAkJ/gsmAgAwAQAAAA==.Draigo:BAAALgAECgIJAgAAAA==.Dreykar:BAABLgAECn8uAAMgAAkJfBi9IwBBAgAgAAkJfBi9IwBBAgAiAAEJ2BxSLQBNAAAAAA==.Drogorn:BAAALgAECgUJDQAAAA==.Druidaezeki:BAAALgAECgIJAgAAAA==.Druidjm:BAAALgADCgMJAwAAAA==.Druvannar:BAAALgADCgEJAQAAAA==.Dröwränger:BAAALgADCgYJCwAAAA==.',
Du='Dultrasenegl:BAABLgAECn8lAAIBAAYJAA3yZQA2AQABAAYJAA3yZQA2AQAAAA==.Dunois:BAAALgAECgIJBgABLgAECgUJCwALAAAAAA==.Duunyangel:BAAALgADCgIJAgAAAA==.',
['Dä']='Dähäkä:BAABLgAECn8dAAIDAAkJJBtSJAB0AgADAAkJJBtSJAB0AgAAAA==.',
Ed='Edazurc:BAAALgAECgQJBAABLgAFFAQJEAABAIcVAA==.Edven:BAACLgAFFH8TAAMXAAMJTAOJJAB5AAAXAAMJTAOJJAB5AAAYAAEJ4QEQQAAcAAAuAAQKfyEAAhcABgnKDMYlAEgBABcABgnKDMYlAEgBAAAA.',
Ei='Eini:BAAALgAECgEJAgAAAA==.',
El='Elbermt:BAAALgAECgEJAQAAAA==.Elbruxão:BAAALgAECgEJAQAAAA==.Eldrick:BAAALgADCgUJDQAAAA==.Eldros:BAAALgAECgYJCAAAAA==.Elementais:BAABLgAECn8kAAIOAAgJFRAKFADvAAAOAAgJFRAKFADvAAAAAA==.Elgado:BAAALgAECgEJAwAAAA==.Elgatadexota:BAAALgADCgkJCgAAAA==.Eliksir:BAAALgAECgUJBQAAAA==.Ellanor:BAABLgAECn8dAAINAAgJ+hifVQDcAQANAAgJ+hifVQDcAQAAAA==.Ellocopere:BAAALgAECgEJAQAAAA==.Elruth:BAAALgADCggJCAABLgAFFAQJDwAfAIoeAA==.Eltão:BAAALgAECgEJBAAAAA==.Elunah:BAAALgADCgQJBAAAAA==.Elwindor:BAAALgAECgEJAQAAAA==.Elyind:BAAALgADCgYJBwAAAA==.Elyn:BAAALgAECgUJEgAAAA==.',
Em='Emmymm:BAAALgAECgEJAQAAAA==.',
En='Endeavour:BAAALgADCgEJAQAAAA==.Enegadiel:BAABLgAECn8tAAIDAAcJdBg8GgD9AAADAAcJdBg8GgD9AAAAAA==.Enoia:BAAALgADCgcJDQAAAA==.',
Eq='Equidnah:BAAALgAECgIJAgAAAA==.',
Er='Erickya:BAAALgAECggJEgAAAA==.Ervadocè:BAABLgAECn8bAAIJAAYJ9RqWNQBBAQAJAAYJ9RqWNQBBAQAAAA==.Ervelino:BAAALgAECgMJBAAAAA==.Eryz:BAAALgAECgMJBQAAAA==.',
Es='Esmeraldth:BAAALgAECgEJAQAAAA==.Esruc:BAAALgAECgEJAQAAAA==.Estrogosbald:BAABLgAECn8ZAAIeAAgJMQzHBgBNAQAeAAgJMQzHBgBNAQAAAA==.',
Eu='Euteinvoco:BAAALgAECgIJAgABLgAFFAMJBQATAM8DAA==.',
Ev='Evely:BAABLgAECn83AAMjAAgJKh4JAQARAgAjAAgJ0hsJAQARAgABAAQJ4R0eGgADAQAAAA==.',
Ex='Exarch:BAACLgAFFH8NAAIWAAQJaRQfFAArAQAWAAQJaRQfFAArAQAuAAQKfysAAhYACQm/IYQDAP4CABYACQm/IYQDAP4CAAAA.',
Fa='Faengar:BAAALgAECgUJCAAAAA==.Falcondk:BAAALgAECgEJAQAAAA==.Falconess:BAAALgADCgEJAQAAAA==.Falkorr:BAAALgAECgEJAQAAAA==.Fandria:BAAALgADCgQJBAAAAA==.',
Fe='Feathria:BAAALgAECgMJAwAAAA==.Felenus:BAAALgAECgQJBAAAAA==.Felguk:BAAALgADCgQJBQAAAA==.Felipebritoo:BAAALgAECgMJBgABLgAECgYJEgALAAAAAA==.Fenrirsp:BAABLgAECn8XAAMkAAgJcyGKGwDoAQAkAAYJpyGKGwDoAQAFAAQJxxrLNQA+AQAAAA==.Ferdruiid:BAAALgAECgEJAQAAAA==.Feropudo:BAAALgADCgkJDgAAAA==.Ferrarig:BAAALgAECgMJBwAAAA==.',
Fi='Figy:BAAALgAECgQJBQAAAA==.Filixy:BAAALgADCgYJBgAAAA==.',
Fl='Flemma:BAABLgAECn8mAAIXAAgJ5Q8OAwBYAQAXAAgJ5Q8OAwBYAQAAAA==.Flexer:BAAALgAECgIJAgAAAA==.Flores:BAAALgADCgMJBgAAAA==.Floridastyle:BAABLgAECn8fAAIFAAUJTxa5NwA0AQAFAAUJTxa5NwA0AQAAAA==.Flux:BAAALgAECgcJDwAAAA==.',
Fo='Foguerosa:BAACLgAFFH8JAAMNAAMJpRyQLwD4AAANAAMJpRyQLwD4AAAlAAEJggBqCAAxAAAuAAQKfxYAAg0ACAlpIVREAGsCAA0ACAlpIVREAGsCAAAA.Folghunthir:BAAALgADCgQJBAAAAA==.Fortis:BAAALgADCgUJBQAAAA==.',
Fr='Frankkquini:BAAALgADCgYJEgAAAA==.Friodokrl:BAACLgAFFH8JAAITAAMJIw4ppwDNAAATAAMJIw4ppwDNAAAuAAQKfzYAAxsACQkHHj4PABcCABsACQkuGz4PABcCABMACAkdGuJEAPQBAAAA.Fritzgerhart:BAAALgAECgEJAQAAAA==.Frostkller:BAAALgADCgIJAgAAAA==.Frostmhaw:BAAALgADCgUJBQAAAA==.Frostreaper:BAAALgAECgQJBgAAAA==.',
Fu='Fubukiofhell:BAACLgAFFH8QAAINAAMJmxrEMwD2AAANAAMJmxrEMwD2AAAuAAQKfxsAAg0ACQkNGllBABgCAA0ACQkNGllBABgCAAAA.Fuginzao:BAAALgAECgEJAQAAAA==.Furtacor:BAAALgAECgEJAgAAAA==.Furyarh:BAAALgAECgMJAwAAAA==.',
['Fö']='Föxhüntër:BAAALgAECgIJAgAAAA==.',
Ga='Gaarpo:BAAALgADCgIJAgAAAA==.Gabana:BAAALgADCgQJBAAAAA==.Gabdobbuh:BAAALgAECgUJCAAAAA==.Gabn:BAAALgAECgMJBgAAAA==.Gabricia:BAAALgADCgIJAgAAAA==.Gafgar:BAAALgADCgUJCQAAAA==.Gaila:BAAALgAECgIJBgAAAA==.Galduin:BAACLgAFFH8HAAIHAAMJ5wy/OQDMAAAHAAMJ5wy/OQDMAAAuAAQKfzQAAgcACQncGbYYACgCAAcACQncGbYYACgCAAAA.',
Ge='Gedexx:BAAALgAECgMJAgAAAA==.Geduntruppa:BAAALgAECgYJBgAAAA==.Gentioiroh:BAAALgAECgQJBAAAAA==.',
Gh='Ghorderp:BAAALgADCgcJDAAAAA==.Ghosstt:BAAALgAECgEJAgAAAA==.Ghoulrozon:BAAALgADCgYJBgAAAA==.',
Gi='Giovannapala:BAABLgAECn8aAAIDAAgJiQ73oAA2AQADAAgJiQ73oAA2AQAAAA==.Giovannasham:BAAALgAECgEJAwAAAA==.Giripoca:BAAALgAECgQJCQAAAA==.',
Gl='Gladsmonge:BAABLgAECn8pAAImAAcJ3h8EFgBqAgAmAAcJ3h8EFgBqAgAAAA==.Glorcckk:BAABLgAECn8XAAIHAAYJKQU8FwCFAAAHAAYJKQU8FwCFAAAAAA==.',
Gn='Gnomagga:BAAALgAECgcJEgABLgAECggJNgAMAB8cAA==.Gnomohabe:BAAALgADCgQJBgAAAA==.',
Go='Goddofwarr:BAAALgADCggJEQAAAA==.Gonb:BAAALgADCgUJBQAAAA==.Goueki:BAABLgAECn80AAMBAAgJmBrZMAAYAgABAAgJmBrZMAAYAgAjAAIJSwEtgwA8AAAAAA==.',
Gr='Greenzle:BAAALgAECgUJBgAAAA==.Grillnborst:BAAALgADCgEJAgAAAA==.Grilonp:BAAALgADCgQJCAAAAA==.Grogath:BAAALgAECgQJCAAAAA==.Grogtixa:BAAALgAECggJCQABLgAECgkJKgAPAFcWAA==.Gromoff:BAABLgAFFH8HAAISAAIJwiREhAC9AAASAAIJwiREhAC9AAAAAA==.Grunmonk:BAAALgADCgEJAQAAAA==.Grømmar:BAAALgADCgMJAwAAAA==.',
Gu='Gudangara:BAAALgAECgUJBgAAAA==.Gugans:BAAALgAECgEJAgAAAA==.Gumy:BAAALgAECgEJBAAAAA==.Guzinbrs:BAAALgADCgYJBgAAAA==.Guztaverdead:BAAALgADCgQJBAAAAA==.',
['Gü']='Güistrong:BAAALgADCgIJAwAAAA==.',
Ha='Haakaí:BAAALgAECgUJEAAAAA==.Haandir:BAAALgAFFAEJAQAAAA==.Hackterin:BAAALgADCgYJBgAAAA==.Hadorah:BAAALgAECgUJBgAAAA==.Haelle:BAAALgAFFAEJAQAAAA==.Haerys:BAAALgAFFAEJAQAAAA==.Hakünamatata:BAAALgAECgUJBQAAAA==.Handhemirr:BAAALgAECgMJBAAAAA==.Haranclaw:BAAALgAECgEJAQAAAA==.Harany:BAABLgAECn8qAAMFAAgJXRe5EgBOAgAFAAgJXRe5EgBOAgAkAAYJWg36FACHAAAAAA==.Harrypotinho:BAABLgAECn83AAISAAkJfhs+JwBAAgASAAkJfhs+JwBAAgAAAA==.Harttas:BAAALgAECgEJAQAAAA==.Haunexd:BAAALgADCgMJAwAAAA==.Havenna:BAAALgAECgUJCAAAAA==.',
He='Headøhunter:BAAALgAECgEJAgAAAA==.Healgate:BAAALgAECgEJAQAAAA==.Heeythaly:BAAALgAECgEJAQAAAA==.Hegekant:BAABLgAFFH8GAAIVAAQJZQrpDQC7AAAVAAQJZQrpDQC7AAAAAA==.Helessa:BAAALgAECgEJAgAAAA==.Hellenah:BAAALgADCggJCAAAAA==.Herablack:BAABLgAFFH8GAAIKAAIJghG9CQCEAAAKAAIJghG9CQCEAAAAAA==.Herika:BAAALgADCgMJAwAAAA==.',
Hi='Hidenz:BAAALgAECgIJAgAAAA==.',
Ho='Hoem:BAAALgAECgMJAwAAAA==.Holand:BAAALgAECgYJDAAAAA==.Holydread:BAAALgAECgIJAgAAAA==.',
Hu='Hulig:BAACLgAFFH8GAAIDAAMJGSGuLQDWAAADAAMJGSGuLQDWAAAuAAQKfykAAwMACAn+H3gnAGYCAAMACAn+H3gnAGYCAAwAAQkBB+dUACcAAAAA.Hunthearthas:BAAALgAECgMJAwAAAA==.',
['Hø']='Høkulani:BAABLgAECn8dAAINAAcJchH+iwBfAQANAAcJchH+iwBfAQAAAA==.',
Ib='Ib:BAAALgAECgMJAwAAAA==.Ibrad:BAAALgAECgQJBAAAAA==.Ibuprofens:BAAALgAECgEJAQAAAA==.',
Ic='Iceyag:BAAALgAECgIJAgAAAA==.',
Ig='Ignisastra:BAAALgAECgQJBAAAAA==.Igryn:BAAALgAFFAIJAgAAAA==.Igthil:BAAALgADCgYJEAAAAA==.',
Ik='Ikiam:BAAALgAECgYJDQAAAA==.Ikslawok:BAAALgAECgUJDwAAAA==.',
Il='Ileria:BAAALgAECgcJCQAAAA==.Iliriana:BAAALgAECgEJAQAAAA==.Illarion:BAAALgADCgQJBAAAAA==.Illidanos:BAABLgAECn8cAAInAAgJ/REqIAB4AQAnAAgJ/REqIAB4AQAAAA==.Illidansan:BAAALgAECgQJBQABLgAECgYJDAALAAAAAA==.Illidris:BAAALgAECgUJBQAAAA==.Illumiinated:BAABLgAECn8UAAIVAAYJiwx/RQCSAAAVAAYJiwx/RQCSAAAAAA==.',
Im='Imathias:BAAALgAECgQJBAAAAA==.',
In='Incarus:BAAALgAECgcJCgAAAA==.Incognita:BAAALgAECgEJAQAAAA==.Indis:BAAALgADCgQJBgAAAA==.Infyniti:BAAALgAECgQJBAAAAA==.Interst:BAAALgAECgEJAQAAAA==.',
Ir='Irandel:BAAALgADCgUJBQAAAA==.Irion:BAAALgAECgQJBQAAAA==.',
Is='Iscalio:BAAALgAECgYJCgAAAA==.',
It='Itatchii:BAAALgAFFAMJBAAAAA==.',
Iu='Iuuh:BAABLgAFFH8NAAICAAMJaRjqEQDUAAACAAMJaRjqEQDUAAAAAA==.',
Iv='Ivinhosilva:BAAALgADCgYJBgAAAA==.',
Ja='Jackdawnsong:BAABLgAECn8bAAINAAkJgxuzOgAuAgANAAkJgxuzOgAuAgAAAA==.Jaene:BAAALgADCgYJDQAAAA==.Jahuun:BAABLgAECn8cAAIDAAcJ7Q1TmwA/AQADAAcJ7Q1TmwA/AQAAAA==.Jamantoso:BAAALgAECgEJAQAAAA==.',
Je='Jeess:BAAALgADCgMJAwAAAA==.Jefflich:BAABLgAECn8jAAMTAAgJ1guUiQBuAQATAAgJgQqUiQBuAQAaAAEJhxJqPAAuAAAAAA==.',
Jg='Jg:BAAALgAECgUJBwAAAA==.',
Ji='Jinknu:BAAALgAECgIJBAAAAA==.',
Jo='Jojoadventur:BAAALgAECgEJAQAAAA==.Jotaloko:BAAALgAECgYJCAAAAA==.Jottapeg:BAAALgADCgcJAwAAAA==.Jowzz:BAAALgADCgQJBAAAAA==.',
Ju='Jubard:BAAALgAECgEJAQAAAA==.Juliamarques:BAAALgAECgMJBAAAAA==.',
['Jü']='Jüllÿe:BAAALgADCgEJAQAAAA==.',
Ka='Kaaellthas:BAAALgAECgQJDQAAAA==.Kacolux:BAAALgADCgEJAQAAAA==.Kaelor:BAAALgADCgYJCQAAAA==.Kaisaargente:BAAALgAECgEJAQAAAA==.Kakarotho:BAAALgAECgMJCQAAAA==.Kalarath:BAAALgAECgYJBgAAAA==.Kaldonios:BAAALgADCgcJEgAAAA==.Kalma:BAAALgAECgEJAQAAAA==.Kamasutram:BAAALgADCgYJCwAAAA==.Kanadriel:BAAALgAECgcJDAAAAA==.Kanarinho:BAABLgAECn80AAIIAAkJIh/2CAApAwAIAAkJIh/2CAApAwAAAA==.Karagume:BAAALgAECgMJBAAAAA==.Kardibito:BAAALgAECgcJDAAAAA==.Karmussie:BAAALgADCgEJAQAAAA==.Karmysh:BAAALgAFFAEJAQAAAA==.Katari:BAAALgAECgYJCgABLgAECgkJIAACAAMfAA==.Kayanz:BAAALgADCgUJBQAAAA==.Kazandra:BAAALgADCgYJBgAAAA==.Kazhadum:BAAALgAECgEJAQAAAA==.',
Ke='Kendars:BAABLgAECn8VAAQJAAYJ0xKfSAAKAQAJAAUJJhKfSAAKAQAIAAUJFQ+5dgDzAAAKAAEJhRUFSwBDAAABLgAFFAMJBwAbALAMAA==.Keox:BAAALgADCgUJBQAAAA==.Ket:BAAALgADCgMJAwAAAA==.Keyallan:BAAALgADCgEJAQAAAA==.',
Kh='Khanmir:BAAALgAECgMJBgAAAA==.Kharon:BAAALgAECgYJCAAAAA==.Khild:BAAALgAECgYJDQAAAA==.Khonar:BAAALgADCgcJDwAAAA==.',
Ki='Killerdek:BAAALgAECgUJBQAAAA==.Killshoty:BAAALgAECgEJAgAAAA==.',
Kl='Klissera:BAAALgADCgQJBAAAAA==.Kluzlocak:BAABLgAECn8iAAIFAAYJUQz6PgAQAQAFAAYJUQz6PgAQAQAAAA==.',
Ko='Komah:BAAALgAECgEJAQAAAA==.Korav:BAAALgAECgMJCQABLgAFFAEJAQALAAAAAA==.Kore:BAABLgAFFH8FAAInAAIJqwl7FgBrAAAnAAIJqwl7FgBrAAABLgAFFAMJEwAVAIkiAA==.Korium:BAAALgADCgUJBQABLgAECgkJOAAGAFckAA==.Koruno:BAAALgADCgYJBgAAAA==.',
Kr='Krosn:BAAALgAECgEJAQAAAA==.Krozhul:BAAALgAECgcJDQAAAA==.Krypthor:BAAALgAECgEJAQAAAA==.Kräupër:BAAALgAECgUJBwAAAA==.',
Ku='Kuatbrz:BAAALgADCgEJAQAAAA==.Kurnous:BAAALgAECgEJAQAAAA==.Kutirenzo:BAAALgADCgUJBwAAAA==.',
['Kä']='Käew:BAAALgAECgEJAQAAAA==.',
La='Labruja:BAAALgAECgEJAQAAAA==.Lafiel:BAABLgAECn8UAAIIAAkJ1RZDQwCUAQAIAAkJ1RZDQwCUAQAAAA==.Lahllis:BAAALgAFFAEJAQAAAA==.Lahnara:BAABLgAECn8VAAIBAAgJGw5qGQAJAQABAAgJGw5qGQAJAQAAAA==.Lamelo:BAAALgADCgYJBgAAAA==.Lanjelanje:BAAALgAECgQJBQAAAA==.Lanmo:BAABLgAFFH8TAAIVAAMJiSIoBwAoAQAVAAMJiSIoBwAoAQAAAA==.Largatixazul:BAAALgADCgUJBgAAAA==.Lataria:BAAALgADCgEJAQAAAA==.Laurea:BAAALgAECgkJEQABLgAECgkJIAACAAMfAA==.',
Le='Ledor:BAAALgAECgUJBwAAAA==.Leebron:BAAALgAECgYJDAAAAA==.Lefthalas:BAAALgAECgUJCgAAAA==.Leitchero:BAAALgAECgIJAgAAAA==.Lemaz:BAAALgAECgEJAQAAAA==.Lemonhunter:BAAALgAECgYJCgAAAA==.Leolock:BAAALgAECgEJAQAAAA==.Leonelmessi:BAAALgAFFAQJAgAAAA==.Lesco:BAAALgADCgMJAwAAAA==.',
Li='Lianele:BAAALgAECgcJDAAAAA==.Liaras:BAABLgAECn8pAAMfAAgJXBeIHgDRAQAfAAgJXBeIHgDRAQAkAAIJzABFaQAmAAAAAA==.Libertinagem:BAAALgAECgYJDQAAAA==.Lichtbaum:BAABLgAECn8nAAMIAAgJoB1aIABAAgAIAAgJoB1aIABAAgAJAAUJwxnVOAAwAQAAAA==.Liftt:BAAALgAECgIJAgAAAA==.Lightsertrop:BAAALgADCgIJAgAAAA==.Liifecomm:BAACLgAFFH8eAAIfAAYJixN3DgBmAQAfAAYJixN3DgBmAQAuAAQKf0cAAh8ACQmIH4ACAEQCAB8ACQmIH4ACAEQCAAAA.Liike:BAAALgAECgcJDQAAAA==.Linestra:BAAALgADCgUJBQAAAA==.Liniak:BAAALgAECgcJEAAAAA==.Liorfield:BAAALgAECgQJCQAAAA==.Liornord:BAAALgAECgUJBgAAAA==.Lipaodrk:BAAALgAECgcJEgAAAA==.Littlepurple:BAACLgAFFH8JAAIgAAMJzxJ7GwD2AAAgAAMJzxJ7GwD2AAAuAAQKfyQAAiAACQl0HJwYAMICACAACQl0HJwYAMICAAAA.',
Lo='Longhai:BAAALgADCgUJCAAAAA==.Lookatmylock:BAABLgAECn8iAAMRAAYJ/xu2DAB0AQARAAYJ/xu2DAB0AQASAAIJmBFNHQFKAAAAAA==.Lordpain:BAAALgAECggJDgAAAA==.Lortherti:BAAALgAECgIJAgAAAA==.Lorwin:BAABLgAECn8UAAIBAAgJhBmbSgDBAQABAAgJhBmbSgDBAQAAAA==.Lotusbr:BAAALgADCgEJAQAAAA==.Louisenacioo:BAABLgAECn8UAAMXAAcJUhCMFQB0AQAXAAcJUhCMFQB0AQAYAAMJqwXgewBpAAAAAA==.Loátrak:BAAALgADCgMJAwAAAA==.',
Lu='Luanne:BAAALgADCgEJAQAAAA==.Luccablack:BAAALgAFFAEJAwAAAA==.Luccagelido:BAACLgAFFH8GAAINAAIJ8wLdWQBqAAANAAIJ8wLdWQBqAAAuAAQKfxYAAg0ABgncC+UiAMcAAA0ABgncC+UiAMcAAAAA.Lucyx:BAAALgAECgUJCQAAAA==.Luidar:BAAALgAECgQJBAAAAA==.Lukaslions:BAABLgAECn8gAAIHAAkJaA8TLACkAQAHAAkJaA8TLACkAQAAAA==.Lukathan:BAAALgADCgQJBAAAAA==.Lunarie:BAAALgAECgYJEwABLgAECgcJBwALAAAAAA==.Luphoe:BAABLgAECn8nAAMIAAcJ9RzHJwAWAgAIAAcJ9RzHJwAWAgAJAAQJkw4kZACLAAAAAA==.Luthira:BAAALgAECgEJAQAAAA==.Luxanä:BAAALgAECgYJCwAAAA==.',
['Lé']='Léio:BAAALgADCgcJCAAAAA==.Léora:BAAALgADCgIJAgAAAA==.',
['Lø']='Lørdsith:BAAALgAECgYJCAABLgAFFAcJAgALAAAAAA==.',
['Lÿ']='Lÿcans:BAAALgADCgEJAQAAAA==.Lÿcäns:BAAALgADCgMJAwAAAA==.',
Ma='Maars:BAAALgAECgEJAgAAAA==.Madagalux:BAABLgAECn8rAAIUAAgJQQr3DwBfAQAUAAgJQQr3DwBfAQAAAA==.Madalenna:BAAALgAECgMJCAAAAA==.Madjack:BAAALgAECgMJAwAAAA==.Madushi:BAAALgAFFAEJAQAAAA==.Madzerø:BAAALgAECgEJBAAAAA==.Magatiun:BAAALgADCgMJBAAAAA==.Magogunt:BAABLgAECn8kAAINAAkJMxHDVADeAQANAAkJMxHDVADeAQAAAA==.Maguul:BAABLgAECn8cAAIMAAkJqRaWEQCrAQAMAAkJqRaWEQCrAQAAAA==.Magzifeh:BAABLgAECn8UAAIBAAcJ3SAkOwDyAQABAAcJ3SAkOwDyAQAAAA==.Mahadevi:BAAALgADCgIJAgAAAA==.Mahdemon:BAAALgAECgYJCQAAAA==.Maiconhood:BAAALgAFFAEJAQAAAA==.Malaks:BAAALgADCgMJAwAAAA==.Malandrvs:BAAALgAFFAEJAwAAAA==.Maljamim:BAAALgADCgIJAgAAAA==.Mamuthwar:BAABLgAECn8ZAAMHAAcJnRgeNgDQAQAHAAcJnRgeNgDQAQAEAAEJMQ7ZQQA1AAAAAA==.Mandingavudu:BAAALgAECgYJBwABLgAFFAEJAQALAAAAAA==.Manei:BAAALgAECgMJAwAAAA==.Mangalarga:BAAALgADCgEJAQAAAA==.Manmoden:BAAALgADCgUJBQABLgAFFAEJAQALAAAAAA==.Mannaton:BAAALgAECgQJBAABLgAFFAEJAQALAAAAAA==.Mannatur:BAABLgAECn8bAAMJAAkJ6hxoEgBDAgAJAAgJ3xtoEgBDAgAVAAgJahf5EQDQAQABLgAFFAEJAQALAAAAAA==.Manopaladino:BAAALgADCgYJBgAAAA==.Manowlo:BAAALgAECgMJAwAAAA==.Manzagon:BAAALgAECgYJCQABLgAFFAEJAQALAAAAAA==.Marandracon:BAAALgADCgMJAwAAAA==.Marmelo:BAAALgADCgQJBAAAAA==.Marretasanta:BAABLgAECn8kAAIDAAcJCRR4jwBTAQADAAcJCRR4jwBTAQAAAA==.Maruterrestr:BAAALgAECgMJAgAAAA==.Marù:BAAALgAECgYJCwAAAA==.Marúh:BAACLgAFFH8SAAIOAAUJPRjaIgBkAQAOAAUJPRjaIgBkAQAuAAQKfykAAg4ACQmQIMQFABYDAA4ACQmQIMQFABYDAAAA.Matedellmor:BAAALgAECgEJAQAAAA==.Matroná:BAAALgAECgEJAQAAAA==.Maxmorf:BAAALgADCgUJBQAAAA==.Mayarabr:BAAALgAFFAEJAQAAAA==.Mazeratos:BAAALgAECgMJBQAAAA==.',
Mc='Mcorelhao:BAAALgADCgEJAQAAAA==.',
Me='Medoza:BAAALgAECgQJBgAAAA==.Megrezz:BAAALgAECgEJAQAAAA==.Mehiel:BAAALgAECgEJAQAAAA==.Mekihlvshtak:BAAALgAECgYJBwAAAA==.Melblaw:BAAALgAECgEJAwAAAA==.Meliøðas:BAAALgADCgEJAQAAAA==.Mendingu:BAABLgAECn8YAAMEAAgJAhwEGwCDAQAHAAgJRxgYKAAdAgAEAAQJ/CAEGwCDAQAAAA==.Mercenarybr:BAAALgAECgEJAgAAAA==.Merumim:BAAALgAECgYJCwAAAA==.Metalgirl:BAAALgADCgYJCwAAAA==.Methamorfo:BAAALgADCggJCQAAAA==.',
Mi='Midrão:BAACLgAFFH8NAAIDAAMJBBLAMADMAAADAAMJBBLAMADMAAAuAAQKfxsAAwMACAkwEaCAAG4BAAMACAkwEaCAAG4BAAwAAgkqBTZPADMAAAAA.Miisuky:BAAALgAECgUJBgAAAA==.Mikasaackerr:BAAALgAECgEJAgAAAA==.Milczarek:BAAALgAECgEJAwAAAA==.Mindlocker:BAABLgAECn8jAAISAAcJMgrJFADFAAASAAcJMgrJFADFAAAAAA==.Minorus:BAAALgAFFAIJBAAAAA==.Mirager:BAAALgAECgQJBAAAAA==.Mistifs:BAABLgAECn8pAAImAAgJ5R1rDwCsAgAmAAgJ5R1rDwCsAgAAAA==.Miticamais:BAAALgAECgQJBQAAAA==.',
Mo='Modogz:BAAALgADCgYJBgAAAA==.Momongadk:BAAALgAFFAEJAQAAAA==.Monkeydking:BAAALgADCgUJBQAAAA==.Morania:BAABLgAECn8XAAIRAAgJUwbrFwDiAAARAAgJUwbrFwDiAAAAAA==.Mordekais:BAAALgAFFAIJBAAAAA==.Morganne:BAAALgAECgEJAQAAAA==.Morinami:BAAALgAECgQJBwAAAA==.Moriyama:BAABLgAECn8rAAMIAAkJOR0wIQA+AgAIAAgJbxwwIQA+AgAJAAIJExJzbABxAAAAAA==.Morphez:BAAALgAECgEJAwABLgAFFAEJAQALAAAAAA==.Morphisz:BAAALgAFFAEJAQAAAA==.Morphiszs:BAAALgAECgMJBQABLgAFFAEJAQALAAAAAA==.Morphizs:BAAALgAECgEJBQABLgAFFAEJAQALAAAAAA==.Morphoss:BAAALgAECgQJBAABLgAFFAEJAQALAAAAAA==.Mortesan:BAAALgAECgEJAQABLgAECgYJDAALAAAAAA==.Moshagun:BAAALgAFFAMJBAABLgAFFAMJEQAGACIYAA==.',
Mp='Mpastor:BAAALgADCgUJBQAAAA==.',
Mu='Muca:BAAALgAECgMJAwAAAA==.Muho:BAAALgADCgEJAQAAAA==.Mukonha:BAABLgAECn8jAAISAAcJeA4RjQAgAQASAAcJeA4RjQAgAQAAAA==.',
My='Myzukim:BAAALgADCgYJBQAAAA==.',
['Mã']='Mãoleves:BAAALgADCgEJAQAAAA==.',
['Må']='Måximus:BAAALgAECgUJCQAAAA==.',
['Mü']='Müller:BAAALgADCgEJAQABLgAECgcJEAALAAAAAA==.',
Na='Naeryndam:BAAALgADCgEJAQAAAA==.Namyara:BAAALgAECgEJAQAAAA==.Narutowow:BAAALgADCgMJAwAAAA==.Natcmd:BAAALgAECgYJCwAAAA==.Nathilell:BAAALgADCgIJAgAAAA==.Naturezo:BAABLgAECn8YAAImAAcJHBzRAwArAgAmAAcJHBzRAwArAgABLgAECggJKgAFAF0XAA==.Navira:BAAALgAECgEJAQAAAA==.Nayanna:BAAALgADCgcJDQAAAA==.Nazzd:BAAALgAECgQJBAABLgAFFAUJCQAgAMwUAA==.',
Ne='Nedy:BAAALgADCgMJAwAAAA==.Negblack:BAACLgAFFH8JAAIBAAMJswodawDOAAABAAMJswodawDOAAAuAAQKfxYAAgEABwkEFrMZAAYBAAEABwkEFrMZAAYBAAAA.Neggi:BAAALgAECgUJBwAAAA==.Nemesysy:BAAALgAECgMJAwAAAA==.Nerphien:BAAALgADCgUJBQAAAA==.Nesktpally:BAAALgAECgcJCAAAAA==.Netbrood:BAAALgADCgUJBgABLgAECgUJBwALAAAAAA==.Netbrother:BAAALgAECgUJBwAAAA==.Nethdorai:BAAALgADCgQJBAAAAA==.Netherbane:BAABLgAECn84AAMEAAkJGxzKDQAMAgAEAAkJGxzKDQAMAgAHAAIJGQ9JpAAxAAAAAA==.Nezuko:BAAALgAECgUJBQABLgAECgkJNwASAH4bAA==.',
Ni='Niar:BAAALgAECgQJBQAAAA==.Nightmære:BAAALgAECgQJCwAAAA==.Nikelina:BAAALgAECgEJAQAAAA==.Nikelok:BAABLgAECn8ZAAISAAcJfgfrogD6AAASAAcJfgfrogD6AAAAAA==.Ninfador:BAABLgAECn8eAAIFAAYJgxerMQBVAQAFAAYJgxerMQBVAQAAAA==.Ninpus:BAAALgAECgMJAwAAAA==.',
No='Noobmasteer:BAAALgADCgIJAgAAAA==.Nooneknow:BAACLgAFFH8HAAITAAQJTBUOlADkAAATAAQJTBUOlADkAAAuAAQKfzkAAhMACQlUIUYWAMECABMACQlUIUYWAMECAAAA.Nosios:BAAALgAECgYJBgAAAA==.Nosrede:BAAALgAECgEJAQAAAA==.Notz:BAAALgADCgMJBAAAAA==.',
Nu='Nucciwarrior:BAAALgAECgUJCAAAAA==.Nuccixama:BAAALgAECgcJCQAAAA==.',
Ny='Nyde:BAAALgAECgMJAwAAAA==.',
['Né']='Néymar:BAAALgAECgIJAgABLgAECgkJGwATABwQAA==.',
['Nø']='Nøar:BAAALgADCgIJAgAAAA==.',
Oa='Oakshlar:BAAALgAFFAEJAgAAAA==.',
Oc='Ocelaris:BAAALgAECgEJAgAAAA==.',
Oh='Ohlu:BAAALgAECgYJCQAAAA==.Ohluh:BAAALgAECgcJDQAAAA==.',
Or='Ormagh:BAAALgADCgYJBgAAAA==.Oryana:BAAALgAECgcJCAAAAA==.Oríon:BAAALgADCgIJAgAAAA==.',
Ot='Otton:BAABLgAECn8qAAIDAAkJagktuwAPAQADAAkJagktuwAPAQAAAA==.',
Ov='Overnigth:BAAALgADCgIJAgAAAA==.Overwalker:BAAALgAECgEJAgAAAA==.Ovosemdente:BAAALgADCgEJAQAAAA==.',
Ow='Owllskull:BAAALgAECgYJEgAAAA==.',
Oz='Ozovo:BAAALgAECgcJEgAAAA==.',
Pa='Pacoka:BAAALgADCgQJBQAAAA==.Padrafferty:BAAALgADCgcJBwAAAA==.Paidesanto:BAABLgAECn8WAAQUAAcJyhAYGwDlAAAUAAYJKg8YGwDlAAASAAYJMgt+0gCwAAARAAMJ5RGTRgCcAAAAAA==.Paidesantox:BAABLgAECn8YAAIJAAcJRAkIRQD4AAAJAAcJRAkIRQD4AAABLgAFFAMJBwAHAOcMAA==.Paidocharles:BAAALgAECgIJBQAAAA==.Paimax:BAAALgAECgEJAQAAAA==.Paladinokun:BAAALgAECgYJDAAAAA==.Palanis:BAAALgAECgcJBwAAAA==.Palazarta:BAABLgAECn8XAAIDAAcJBAqRvgAKAQADAAcJBAqRvgAKAQAAAA==.Pancetá:BAAALgAFFAEJAQAAAA==.Pandadruid:BAAALgADCgMJAwAAAA==.Pandavoli:BAAALgAECgUJDAAAAA==.Pangolinho:BAAALgAECgQJBgAAAA==.Panky:BAAALgAECgQJBAAAAA==.Panquecudo:BAAALgADCgIJAgAAAA==.',
Pd='Pdois:BAAALgADCgMJAwAAAA==.',
Pe='Pesscador:BAAALgAECgMJAwAAAA==.Petrolesk:BAAALgAECgYJEwAAAA==.Pex:BAAALgAECgEJAwAAAA==.',
Pi='Piriguetee:BAAALgADCgEJAQAAAA==.Pirro:BAAALgAECgEJAQAAAA==.Pisadinha:BAAALgADCgcJBwAAAA==.',
Pk='Pkzimn:BAAALgADCgUJBQAAAA==.',
Pl='Playsson:BAAALgAECgYJEwAAAA==.Plottwist:BAAALgADCgcJDwABLgAECgkJQgATAPobAA==.',
Po='Pogonus:BAAALgADCgIJAgAAAA==.Pontocego:BAAALgAECgQJBAAAAA==.Pororocaa:BAAALgAECgQJCAAAAA==.Posturado:BAAALgADCgEJAQAAAA==.Powerworth:BAAALgAECgEJAQAAAA==.',
Pr='Pravios:BAAALgAECggJDgAAAA==.Priestkill:BAAALgADCgcJCQAAAA==.Prikithon:BAAALgAECgEJAQAAAA==.Primewolf:BAAALgAECgMJAwAAAA==.',
Ps='Psicomanic:BAAALgADCgMJAwAAAA==.',
Pt='Pterodactilo:BAAALgAECgYJAQAAAA==.',
Pu='Puherito:BAAALgAECggJEAAAAA==.Purgas:BAAALgAFFAEJAQAAAA==.Purifc:BAAALgAECgEJAQAAAA==.',
Qu='Quartohokage:BAAALgADCgEJAQAAAA==.Quinthalam:BAAALgADCgMJAwAAAA==.',
Ra='Radathewhite:BAAALgAECgMJAwAAAA==.Rafac:BAAALgAECgEJAgABLgAFFAEJAQALAAAAAA==.Rafazinho:BAAALgADCgQJBAAAAA==.Ramyna:BAAALgAECgMJBQAAAA==.Ramyra:BAAALgADCgcJDQAAAA==.Raphaeldh:BAAALgAECgEJAgAAAA==.Raphahunterr:BAAALgADCgEJAQAAAA==.Raposa:BAAALgADCgEJAQAAAA==.Raposinha:BAAALgADCgMJAwAAAA==.Rarkway:BAAALgAECgcJCwAAAA==.Ravenblak:BAAALgADCgMJAwAAAA==.Rayanne:BAAALgADCgYJBgAAAA==.Raycujoh:BAAALgAECgEJAQAAAA==.',
Re='Reckfull:BAAALgAECgYJBgAAAA==.Regininha:BAAALgAECgEJAQAAAA==.Reigeladinho:BAAALgAECgcJCQAAAA==.Reloumifrend:BAAALgAECgcJCgAAAA==.Rendros:BAAALgADCgUJBQAAAA==.Retrib:BAAALgADCgEJAQAAAA==.',
Rh='Rhaegaar:BAAALgAECgcJDQAAAA==.Rhanideri:BAAALgADCgEJAQAAAA==.Rhodinius:BAAALgAECgMJCAAAAA==.',
Ri='Rivotreel:BAAALgADCgQJBAAAAA==.',
Ro='Robeerth:BAACLgAFFH8QAAIBAAQJhxVsHAA6AQABAAQJhxVsHAA6AQAuAAQKfxsABAEACQnIHOAIAOQBAAEACQnIHOAIAOQBABYAAQnnEt1ZAEYAACMAAQkAAENJAAAAAAAA.Rochera:BAAALgAECgEJAQAAAA==.Rokhanar:BAAALgAECgUJCwAAAA==.',
Ru='Rudemonster:BAAALgAECgEJAQAAAA==.Rughaz:BAAALgAECgYJBwAAAA==.Ruhtarr:BAAALgADCgEJAQAAAA==.Runak:BAAALgADCgIJAgAAAA==.',
Ry='Ryukato:BAAALgAECgQJBQAAAA==.',
Sa='Saek:BAAALgAECgcJEgAAAA==.Saelorth:BAAALgAECgUJCgAAAA==.Sakurachan:BAAALgADCgUJBQAAAA==.Salaciel:BAAALgAECgYJCQAAAA==.Samaelreveng:BAAALgAECgQJBAAAAA==.Sanderclone:BAAALgAECgEJAQAAAA==.Sanguenafaca:BAAALgADCgYJCgAAAA==.Santiss:BAABLgAECn8WAAIDAAYJDhWZqQApAQADAAYJDhWZqQApAQAAAA==.Santorini:BAAALgAECgcJDQAAAA==.Saphirot:BAAALgADCgUJBQAAAA==.Saphis:BAAALgADCgEJAQAAAA==.Sardado:BAAALgAECgEJAQAAAA==.Sardron:BAAALgAECgEJAQAAAA==.Satanaris:BAAALgADCgEJAQAAAA==.',
Sc='Scanorr:BAAALgAECgYJDQAAAA==.Scheffers:BAABLgAECn8YAAIkAAYJwRMsNgA9AQAkAAYJwRMsNgA9AQAAAA==.',
Se='Selah:BAAALgADCgQJBgAAAA==.Selver:BAAALgAECgcJCAABLgAFFAkJMAAkAD8ZAA==.Selüne:BAAALgAECgcJDQAAAA==.Sephora:BAAALgAECgYJCwABLgAECggJKQAfAFwXAA==.Sero:BAAALgAECgEJAQAAAA==.Sevagoth:BAAALgAECggJDQAAAA==.',
Sh='Shadowlock:BAAALgADCgIJAQABLgAECgYJFAAgAN8UAA==.Shadowmornac:BAAALgAECgMJBgAAAA==.Shallkiller:BAAALgAECgIJAgAAAA==.Shamanica:BAAALgAECgEJAgAAAA==.Shamateus:BAAALgADCggJEwAAAA==.Shaora:BAAALgAECgQJCAAAAA==.Shasuna:BAAALgADCgIJAgAAAA==.Shaunnun:BAAALgADCgEJAQAAAA==.Shenloong:BAAALgADCgYJBgABLgAECgYJDQALAAAAAA==.Shieldhonor:BAAALgADCgYJCQAAAA==.Shinnók:BAAALgAECgIJAgAAAA==.Shiíro:BAAALgAFFAIJBAABLgAFFAUJEwADABAkAA==.Shuruupita:BAAALgAECgMJBQAAAA==.Shynato:BAAALgADCgEJAQAAAA==.Shynock:BAAALgADCgEJAQAAAA==.Shyriull:BAAALgAECgEJAQAAAA==.Shyzuno:BAAALgADCgQJBAAAAA==.Shãka:BAAALgADCgMJAwAAAA==.',
Si='Siladriel:BAAALgADCgMJAwAAAA==.Silfirrion:BAAALgADCgEJAQABLgAFFAIJBgAUAMkYAA==.Silvanna:BAABLgAECn8XAAIBAAYJoQ8pGQALAQABAAYJoQ8pGQALAQAAAA==.Silvao:BAAALgAECgYJBgAAAA==.Sirgonzo:BAABLgAECn8XAAIDAAkJtxdwPgAMAgADAAkJtxdwPgAMAgAAAA==.',
Sk='Skullexus:BAAALgAECgMJBAAAAA==.Skunkbr:BAAALgADCgEJAQAAAA==.',
Sl='Sleepychety:BAAALgAECgUJBgAAAA==.Slowsmoke:BAAALgADCgYJBwAAAA==.Slyfer:BAABLgAFFH8GAAIBAAIJwRQ4gACYAAABAAIJwRQ4gACYAAAAAA==.',
Sn='Snatzz:BAAALgADCgMJAgAAAA==.',
So='Soggoth:BAAALgADCgkJCQAAAA==.Solk:BAAALgAECgMJBgAAAA==.Sonne:BAAALgAECgMJAwABLgAFFAMJDQATABwNAA==.Sontarfury:BAAALgAECgEJAQAAAA==.Soray:BAAALgAECgYJCQAAAA==.Sorim:BAABLgAECn8sAAIIAAkJoxorHABlAgAIAAkJoxorHABlAgAAAA==.Soryan:BAABLgAECn8tAAMIAAkJxhTTLwDkAQAIAAkJxhTTLwDkAQAJAAUJ+g3yUADKAAAAAA==.Soulassassin:BAAALgADCgIJAwAAAA==.Soulhell:BAABLgAECn8cAAIFAAYJaxQbNQBBAQAFAAYJaxQbNQBBAQAAAA==.',
Sp='Spartanlofs:BAAALgADCgcJEQAAAA==.Spawndeath:BAAALgADCgEJAQAAAA==.Spezia:BAAALgAECgYJDQAAAA==.',
Sr='Srluizz:BAAALgAECgIJAgAAAA==.',
Ss='Ssushii:BAAALgAECgEJAQAAAA==.',
St='Staffkiller:BAABLgAECn8aAAINAAgJ6QfXGAALAQANAAgJ6QfXGAALAQAAAA==.Stellån:BAAALgADCgcJCAAAAA==.Stigmata:BAAALgAECgEJAgAAAA==.Stixlightmix:BAABLgAFFH8FAAMhAAMJ5hFXLgCPAAAhAAIJORhXLgCPAAAoAAEJQAWZXwAxAAAAAA==.Stixmixdk:BAABLgAFFH8FAAIbAAMJIhaCMgByAAAbAAMJIhaCMgByAAAAAA==.Stixmixwarr:BAAALgAFFAYJAQAAAA==.Straz:BAAALgADCgQJBAAAAA==.Strongman:BAAALgAECgYJBgAAAA==.Strygah:BAAALgADCgQJBAAAAA==.Stx:BAAALgAECgYJEwAAAA==.',
Su='Subsdk:BAACLgAFFH8VAAITAAYJpQ8KQwBvAQATAAYJpQ8KQwBvAQAuAAQKfyYAAxMACAkeHs9AAAECABMACAkeHs9AAAECABoAAQnfH6owAFsAAAAA.Suih:BAAALgADCgUJBQAAAA==.Sunwalkers:BAAALgAECgUJBgAAAA==.Supfurry:BAABLgAFFH8GAAIYAAIJYAySLQBdAAAYAAIJYAySLQBdAAAAAA==.Sushhi:BAABLgAFFH8FAAITAAMJ5hK5QwDSAAATAAMJ5hK5QwDSAAAAAA==.Suushy:BAAALgAECgYJEAABLgAFFAMJBQATAOYSAA==.',
Sw='Swam:BAAALgAFFAMJBAABLgAFFAMJEwAVAIkiAA==.Sweetl:BAAALgAECgQJBAAAAA==.',
Sy='Syreenaa:BAAALgAECgIJAwAAAA==.Systeni:BAAALgADCgkJCwAAAA==.',
['Sä']='Säek:BAAALgAECgMJCAAAAA==.',
['Sø']='Søøssø:BAAALgAECgYJCAAAAA==.',
Ta='Tacaagua:BAAALgAECgIJAwAAAA==.Taha:BAAALgAECgYJDgAAAA==.Taillys:BAAALgADCgMJBAAAAA==.Tainy:BAAALgAECgEJAQAAAA==.Takemywand:BAAALgADCgUJBQABLgAECgcJFAAXAFIQAA==.Takenaka:BAAALgADCgMJAwAAAA==.Tarez:BAAALgAFFAEJAQAAAA==.Tarfonir:BAAALgAECgYJCQAAAA==.Tashian:BAAALgADCgIJAgAAAA==.Tavalira:BAAALgADCgYJBgAAAA==.Taylör:BAAALgADCgEJAQAAAA==.',
Te='Tealen:BAAALgAECgEJAQAAAA==.Ted:BAAALgAECgcJDAAAAA==.Teiseken:BAAALgAECgcJBwAAAA==.Telaskei:BAAALgAECgUJBQAAAA==.Tempesfúria:BAAALgADCgIJAgAAAA==.Tenébria:BAAALgAECgcJBwAAAA==.Teratsemknk:BAAALgAECgUJBQAAAA==.',
Th='Thalyndrah:BAAALgADCgEJAQAAAA==.Tharnforge:BAAALgAECgEJAQAAAA==.Thejokker:BAACLgAFFH8IAAIHAAMJ9AAWTABvAAAHAAMJ9AAWTABvAAAuAAQKfxcAAgcABwl6BKVoALwAAAcABwl6BKVoALwAAAAA.Themooster:BAACLgAFFH8VAAMMAAQJqBAqBgDCAAAMAAQJTBAqBgDCAAADAAIJYg2gkgCOAAAuAAQKfxQABAwACQkWE5cDAIoBAAwABwkKFpcDAIoBAAMABAnyCOkJAawAAAIAAQnGCDyYACgAAAAA.Thepickles:BAABLgAECn8fAAIDAAcJ7gsYHADvAAADAAcJ7gsYHADvAAAAAA==.Thepunk:BAAALgAECgQJEQAAAA==.Thesindorei:BAAALgAFFAEJAQAAAA==.Thintor:BAAALgADCgEJAQAAAA==.Thormento:BAABLgAECn8YAAIOAAcJQhSfWgBOAQAOAAcJQhSfWgBOAQAAAA==.Thraell:BAAALgAECgEJAQAAAA==.Threeß:BAAALgAECgQJBQAAAA==.',
Ti='Tigerblood:BAAALgADCgUJBQAAAA==.Tipooreeii:BAAALgADCgEJAQAAAA==.Tiriricao:BAAALgAECgIJAwAAAA==.Titanicos:BAAALgAFFAIJAgAAAA==.',
Tj='Tjhunter:BAABLgAECn8fAAIBAAgJnQpeSQCNAQABAAgJnQpeSQCNAQAAAA==.',
To='Tobbiy:BAACLgAFFH8IAAIbAAMJWxifIgDXAAAbAAMJWxifIgDXAAAuAAQKfxUAAxsABgk+Ge4WALABABsABgk+Ge4WALABABMAAgmJBIJmAT0AAAAA.Toddyb:BAABLgAFFH8FAAIBAAMJoSDFIwAUAQABAAMJoSDFIwAUAQABLgAFFAMJDQADABwiAA==.Tonytornado:BAAALgAECgEJAgAAAA==.',
Tr='Tranca:BAAALgADCgUJAwAAAA==.Tranh:BAAALgADCgkJFQAAAA==.Traxer:BAAALgADCgQJBAAAAA==.Tripäsecä:BAAALgAECgcJDgAAAA==.Troladora:BAABLgAECn8VAAINAAYJqA75wwAEAQANAAYJqA75wwAEAQAAAA==.Trévor:BAAALgAECgEJAQAAAA==.',
Ts='Tsreis:BAAALgADCgEJAQAAAA==.',
Tu='Tutydias:BAABLgAFFH8FAAINAAMJ5gM4UwCIAAANAAMJ5gM4UwCIAAAAAA==.',
Tw='Twoheavy:BAAALgADCgkJCQABLgAECgYJCQALAAAAAA==.',
Ty='Tyrandrisa:BAAALgADCgIJAQAAAA==.',
['Tá']='Tátu:BAAALgADCgMJAwAAAA==.',
Uh='Uhdyr:BAAALgAECgQJBQAAAA==.',
Um='Ummetrodefio:BAAALgADCgEJAQAAAA==.',
Un='Unklevi:BAAALgADCgEJAQAAAA==.',
Ur='Urthemiel:BAAALgAECgEJAQABLgAECgYJCAALAAAAAA==.',
Us='Usodeplantas:BAAALgAFFAEJAQABLgAFFAQJFQAMAKgQAA==.',
Ut='Uthred:BAACLgAFFH8GAAMTAAMJnwGH1wCKAAATAAMJnwGH1wCKAAAaAAIJUgAPKwA8AAAuAAQKfzEABBMACQkdB12aADUBABMACQnOBF2aADUBABoABgmqBG8MAOsAABsAAwmuCblKAGMAAAAA.',
Va='Vaelryn:BAAALgAECgYJCQABLgAECgYJCAALAAAAAA==.Vagabundinho:BAAALgAECgQJBQAAAA==.Valakirt:BAAALgADCgEJAQAAAA==.Valdemmon:BAAALgAECgQJBwAAAA==.Valororo:BAABLgAECn8bAAINAAkJtAYHjgBbAQANAAkJtAYHjgBbAQAAAA==.Vandlesh:BAABLgAECn8WAAINAAcJBw05pwAvAQANAAcJBw05pwAvAQAAAA==.Vardha:BAAALgADCgQJBAAAAA==.Varka:BAAALgADCgYJGQAAAA==.',
Ve='Velkharun:BAAALgAECgQJDAABLgAFFAQJEAABAIcVAA==.Velkryon:BAAALgAECgUJBgAAAA==.Veltharyn:BAAALgAFFAEJAQAAAA==.Venatrin:BAAALgADCgkJCQAAAA==.Vess:BAAALgAECgQJBAAAAA==.Vexxv:BAABLgAECn8UAAITAAUJshqnigBrAQATAAUJshqnigBrAQAAAA==.Vexxz:BAAALgAECgcJDAAAAA==.',
Vh='Vhaeraun:BAAALgAECgYJBgAAAA==.',
Vi='Viquue:BAAALgADCgYJBgAAAA==.Viuvo:BAAALgADCgMJAwAAAA==.Vivisoft:BAAALgADCgMJAwAAAA==.',
Vl='Vlannytic:BAAALgAECgMJAwAAAA==.',
Vo='Voidrb:BAAALgADCgcJBwABLgAECggJGAAEAAIcAA==.Vovogamer:BAAALgAECgQJBgAAAA==.',
Vu='Vunks:BAAALgAFFAEJAQAAAA==.',
['Vò']='Vòxs:BAACLgAFFH8SAAMEAAQJohSlIwDhAAAEAAMJhxilIwDhAAAHAAIJug/bQwCSAAAuAAQKf0sAAwQACAk8JLYDAMQCAAQABwnDJLYDAMQCAAcABglHHoQuAPcBAAAA.',
Wa='Walkery:BAAALgADCgIJAgAAAA==.Wattari:BAABLgAECn8bAAIGAAYJDgTROwCEAAAGAAYJDgTROwCEAAAAAA==.Watters:BAEALgAECgUJCwABLgAFFAQJFwAFAL8QAA==.',
Wh='Whiteep:BAAALgADCgYJCAAAAA==.Whitersoul:BAACLgAFFH8KAAINAAUJNQ/LLQAVAQANAAUJNQ/LLQAVAQAuAAQKf1EAAg0ACQmrIJ0CAPsCAA0ACQmrIJ0CAPsCAAAA.Whiteseraph:BAAALgADCgEJAQAAAA==.Whynchester:BAAALgADCgEJAQAAAA==.',
Wi='Wiilami:BAAALgADCgMJAwAAAA==.Windsailor:BAAALgAECgUJBQAAAA==.Wiserys:BAACLgAFFH8IAAISAAMJvBJJhAC9AAASAAMJvBJJhAC9AAAuAAQKfzMAAxIACQmpIoYWAJ0CABIACQnmIYYWAJ0CABQABgn+HBwLAKwBAAAA.',
Wm='Wmarcão:BAABLgAECn8dAAMSAAcJrg/wEADuAAARAAYJlA+YFgDwAAASAAcJ3A3wEADuAAAAAA==.',
Wo='Wolfiez:BAAALgAECgUJDAAAAA==.Wolfnwar:BAAALgAECgQJEAAAAA==.Wopz:BAAALgADCgcJBwAAAA==.Worq:BAAALgADCgYJBgAAAA==.',
Wq='Wqz:BAACLgAFFH8GAAIBAAMJ7Ru/PQCyAAABAAMJ7Ru/PQCyAAAuAAQKfxcAAgEABwnHGZM2ANQBAAEABwnHGZM2ANQBAAAA.',
Wu='Wunamuno:BAAALgAECgEJAQAAAA==.',
Xa='Xallatath:BAAALgADCgUJBQAAAA==.Xamela:BAAALgADCgMJAwAAAA==.Xamãna:BAAALgAECgQJCQAAAA==.',
Xb='Xbleidexx:BAAALgADCgYJBgAAAA==.',
Xe='Xevron:BAAALgAECgQJBAAAAA==.Xexnetw:BAAALgAECgQJDQAAAA==.Xexnew:BAACLgAFFH8FAAIbAAIJLg6rNgBbAAAbAAIJLg6rNgBbAAAuAAQKfxkAAxsACQn0GuAPAA0CABsACQn0GuAPAA0CABMAAQlpB52QAScAAAAA.',
Xf='Xframengox:BAAALgADCgEJAQAAAA==.',
Xi='Xidevill:BAABLgAECn8jAAInAAYJ8Qi5EACKAAAnAAYJ8Qi5EACKAAAAAA==.Xinthorak:BAAALgADCgEJAgAAAA==.Xinzhou:BAAALgADCgQJCAAAAA==.Xiseth:BAAALgAECgIJAgAAAA==.Xixíca:BAAALgADCgUJBgAAAA==.',
Xl='Xladymaladax:BAAALgAECgUJBgAAAA==.',
Xm='Xmari:BAAALgAECgYJCAAAAA==.',
Xn='Xnyx:BAAALgAECgQJBAAAAA==.',
Xo='Xots:BAAALgAFFAEJAgAAAA==.',
Xs='Xseth:BAAALgAECgYJBwAAAA==.',
Xt='Xtremetanke:BAAALgAECgYJDQAAAA==.',
Xu='Xulaman:BAAALgAECgcJDgAAAA==.Xungodz:BAAALgADCgQJBAAAAA==.Xunxu:BAABLgAECn8ZAAMDAAYJdhMQhwBsAQADAAYJdhMQhwBsAQACAAEJJgM2ngArAAAAAA==.',
Xx='Xxcantsidex:BAAALgAECgkJDwAAAA==.',
Xy='Xynrath:BAAALgADCgMJAwAAAA==.',
['Xÿ']='Xÿon:BAAALgAECgEJAQAAAA==.',
Ya='Yamëte:BAAALgAECgYJCgAAAA==.Yangyung:BAAALgAECgEJAQAAAA==.Yannadcg:BAACLgAFFH8GAAIfAAQJ9gJbIgCoAAAfAAQJ9gJbIgCoAAAuAAQKfy8AAh8ACQmRDCcqAHcBAB8ACQmRDCcqAHcBAAAA.',
Yo='Yorickundyer:BAAALgAECgYJCgAAAA==.Youdie:BAABLgAECn8YAAIkAAgJhRLwKgCEAQAkAAgJhRLwKgCEAQAAAA==.',
Yu='Yulthuan:BAAALgADCgMJAwAAAA==.',
Yv='Yvernus:BAAALgAECgQJBgAAAA==.',
Yz='Yziepala:BAAALgAECgMJBAAAAA==.',
Za='Zaaraki:BAABLgAECn9CAAMTAAkJ+hv8BQAPAgATAAkJfBv8BQAPAgAbAAgJ+hYKIgBCAQAAAA==.Zarolho:BAABLgAECn8VAAIPAAYJSA6EUAAFAQAPAAYJSA6EUAAFAQAAAA==.',
Ze='Zeddh:BAAALgAECgEJAQABLgAFFAIJAgALAAAAAA==.Zeddxz:BAAALgAFFAEJAQABLgAFFAIJAgALAAAAAA==.Zenitsua:BAAALgAECgcJCgAAAA==.Zenzeluk:BAAALgAECgMJAwAAAA==.Zephiir:BAABLgAECn8jAAIDAAYJIxj4IADQAAADAAYJIxj4IADQAAAAAA==.Zerdrax:BAAALgAECgIJAgAAAA==.Zeroxyz:BAAALgADCgYJBgABLgAECgYJGAAgAJUPAA==.Zeryen:BAAALgAECgEJAQAAAA==.',
Zf='Zfuntz:BAAALgAECgEJAgAAAA==.',
Zh='Zhunka:BAAALgADCgEJAwAAAA==.',
Zi='Ziikiipala:BAAALgAECgMJBAAAAA==.',
Zo='Zornak:BAAALgADCgUJBQAAAA==.',
Zz='Zzx:BAAALgADCgcJBwAAAA==.',
['Zé']='Zécasete:BAAALgADCgUJBwAAAA==.',
['Ál']='Álucard:BAABLgAECn8bAAITAAkJHBDzFAABAQATAAkJHBDzFAABAQAAAA==.',
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
