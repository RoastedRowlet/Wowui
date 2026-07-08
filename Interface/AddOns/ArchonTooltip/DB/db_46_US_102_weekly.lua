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

local lookup = {'Hunter-BeastMastery','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Druid-Restoration','Druid-Balance','Druid-Feral','Paladin-Protection','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','DeathKnight-Unholy','Warlock-Affliction','Druid-Guardian','Warrior-Fury','Hunter-Survival','Warrior-Protection','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Frost','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','DemonHunter-Devourer','Monk-Windwalker','DemonHunter-Vengeance','Mage-Arcane','Hunter-Marksmanship','Priest-Shadow','Priest-Discipline','Mage-Fire','Monk-Mistweaver','DemonHunter-Havoc','Monk-Brewmaster',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abortheira:BAAALgADCgUJBQAAAA==.',
Ac='Acelord:BAABLgAECn8jAAIBAAkJbxjFJQBLAgABAAkJbxjFJQBLAgAAAA==.Actaeon:BAAALgAECgQJBgAAAA==.',
Ad='Adaar:BAAALgAECgEJAQAAAA==.Adadebox:BAABLgAECn8ZAAMCAAYJXh9FHQAZAgACAAYJXh9FHQAZAgADAAEJhgilRQAkAAAAAA==.Adakat:BAAALgADCgEJAQAAAA==.Adanthedark:BAAALgADCgIJAgAAAA==.Adariom:BAAALgADCgUJCAAAAA==.Adilma:BAAALgAECgUJBgAAAA==.Adrian:BAAALgADCgEJAQAAAA==.Adriannos:BAAALgAECgEJAQAAAA==.',
Ae='Aethir:BAAALgADCgYJBwAAAA==.',
Ag='Agakii:BAAALgADCgEJAQAAAA==.Aghatta:BAAALgAECgcJBwAAAA==.Agonyy:BAAALgAECgUJEAAAAA==.Agrias:BAAALgAECgEJAgAAAA==.',
Ah='Aharadack:BAAALgAECgIJAgAAAA==.',
Ak='Akawaka:BAAALgAECgEJAQAAAA==.Akiji:BAAALgAECgIJBgAAAA==.Akimurad:BAAALgAECgYJBwAAAA==.',
Al='Alakazam:BAAALgADCgcJBwAAAA==.Alanie:BAAALgADCggJCAABLgAFFAIJBAAEAAAAAA==.Ald:BAAALgAECgEJAgAAAA==.Aldebaraum:BAAALgAECgcJDQAAAA==.Alexextreme:BAABLgAECn8WAAIBAAcJ8gYDqADyAAABAAcJ8gYDqADyAAAAAA==.Aliaksandr:BAAALgAECgEJAQAAAA==.Alikth:BAAALgADCgYJBgAAAA==.Alista:BAAALgAECgQJAwAAAA==.Allandyr:BAACLgAFFH8VAAIBAAMJRRZsIQDpAAABAAMJRRZsIQDpAAAuAAQKf2MAAgEACQl+HIcCAGoCAAEACQl+HIcCAGoCAAAA.Alvarao:BAAALgAECgQJBAAAAA==.',
Am='Amandadark:BAAALgAECgEJAgAAAA==.Amano:BAAALgADCgYJDAAAAA==.',
An='Anamia:BAAALgAECgEJAgABLgAFFAIJBAAEAAAAAA==.Anaxthacia:BAAALgADCgMJAwAAAA==.Andarilho:BAAALgAECgYJBwAAAA==.Andinth:BAAALgAECgIJAgAAAA==.Andrepvp:BAAALgADCggJDwAAAA==.Andrit:BAAALgADCgEJAQAAAA==.Anelie:BAAALgAFFAIJBAAAAA==.Anellÿ:BAAALgAECgIJAwAAAA==.Angelloz:BAABLgAECn8rAAIDAAgJARK0fAB1AQADAAgJARK0fAB1AQAAAA==.Anjelvs:BAAALgAECgYJBgAAAA==.Anksunamoon:BAACLgAFFH8HAAIFAAUJoweLMQDpAAAFAAUJoweLMQDpAAAuAAQKfyMABAYACQlEERk3ADkBAAYABgm4Dhk3ADkBAAUACAl7Ea0GAPUAAAcAAgk+EFY8AGgAAAAA.Annaoh:BAABLgAECn8cAAIDAAgJVB3RQQABAgADAAgJVB3RQQABAgAAAA==.Annedin:BAAALgAECgEJBAABLgAECgUJBgAEAAAAAA==.Annia:BAAALgADCgYJBwAAAA==.Anyid:BAAALgAECgMJBQAAAA==.Anãodengoso:BAABLgAECn8pAAMDAAgJSCZgFQDpAgADAAgJSCZgFQDpAgAIAAIJIxLBPQBmAAABLgAECggJKQADAEgmAA==.',
Ap='Apökalÿpsïs:BAACLgAFFH8GAAIJAAMJSwu3LQDLAAAJAAMJSwu3LQDLAAAuAAQKfzIAAgkACQnPG5AdAKsCAAkACQnPG5AdAKsCAAAA.',
Aq='Aquadel:BAAALgAECgMJAwAAAA==.',
Ar='Arator:BAAALgAECggJDwAAAA==.Ardry:BAAALgADCgYJBgAAAA==.Argaloth:BAAALgAECgYJBwAAAA==.Argonzinha:BAAALgAECgEJAQAAAA==.',
As='Asassincego:BAAALgADCgIJAgAAAA==.Ashryel:BAAALgAECgEJAQAAAA==.Ashthon:BAABLgAECn8eAAIBAAcJgxxINgDVAQABAAcJgxxINgDVAQAAAA==.Ashyashiida:BAAALgADCgEJAQAAAA==.Asmitta:BAAALgADCgQJBAAAAA==.',
At='Atalantha:BAAALgAECgIJAgAAAA==.Athelass:BAAALgAECgEJAQAAAA==.Atomicdk:BAAALgAECgUJCgAAAA==.Atomictank:BAAALgAECgcJEwAAAA==.Atonos:BAAALgAECgcJDgAAAA==.',
Au='Auquenai:BAAALgADCgUJBQAAAA==.Aurielis:BAAALgAECgEJAgAAAA==.',
Av='Averagemage:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAAALgAECgQJBAAAAA==.',
Az='Azadium:BAAALgAECgUJCgAAAA==.Azul:BAAALgAECgUJCwAAAA==.',
Ba='Baala:BAAALgAECgEJAgAAAA==.Babalysaga:BAAALgAECgMJAwAAAA==.Badayaga:BAAALgADCgIJAgAAAA==.Bakunogrind:BAAALgAECgUJBQABLgAFFAQJBwAKAEMeAA==.Balragouldur:BAAALgAECgQJBgAAAA==.Balthar:BAACLgAFFH8HAAQKAAIJqAV8bgBgAAAKAAIJqAV8bgBgAAALAAIJfwI9UQBRAAAMAAEJ5gJuHQA3AAAuAAQKfyAABAsABwk6Ek9KAAsBAAsABwmjEU9KAAsBAAwABAkKEWsdAPUAAAoABAkGD26qAHQAAAAA.Barathrum:BAAALgAECgEJAQAAAA==.Barcaldas:BAAALgAECgUJBgAAAA==.Barrocø:BAAALgAECgQJBQABLgAECggJGAANAAIcAA==.Basara:BAAALgAECgcJEgAAAA==.Batefraco:BAAALgADCgIJAgAAAA==.',
Bb='Bbiel:BAABLgAECn8nAAMOAAYJnRMAFAAQAQAOAAYJnRMAFAAQAQAPAAQJwQZl7QCFAAAAAA==.',
Be='Beatriz:BAAALgAFFAEJAQAAAA==.Beelgarath:BAAALgAECgYJDgAAAA==.Beherit:BAAALgAECgMJBgAAAA==.Beliall:BAAALgAECgQJBwAAAA==.Belowlight:BAAALgAECgYJEAAAAA==.Belttazar:BAAALgADCgkJDwAAAA==.Bemmaith:BAAALgAECgQJBAAAAA==.Benzema:BAAALgADCgMJAgABLgAECgkJGwAQABwQAA==.Berzan:BAAALgAECgUJCwAAAA==.Beyoond:BAACLgAFFH8fAAQPAAUJrxURcQDfAAAPAAMJFBURcQDfAAARAAIJgBdUIQBPAAAOAAEJ+wcYJwBHAAAuAAQKfzoABA8ACQm+HGElAEkCAA8ACQm/G2ElAEkCAA4ABAm3D+cxAPEAABEAAwnBFrsfAMMAAAAA.',
Bh='Bhalin:BAAALgAECgUJCQABLgAFFAMJBgADABkhAA==.',
Bi='Bielinski:BAAALgAECgQJBAAAAA==.Biinarc:BAAALgAECgEJAQAAAA==.',
Bl='Blackdut:BAACLgAFFH8MAAIPAAMJkgXTLgCfAAAPAAMJkgXTLgCfAAAuAAQKfxUAAw8ABwmyEWtuAF8BAA8ABwl5EWtuAF8BAA4ABAkpCtYlAIYAAAAA.Blackfear:BAABLgAFFH8FAAISAAMJUwu3DgCGAAASAAMJUwu3DgCGAAABLgAFFAQJCwABALELAA==.Blackrøse:BAAALgADCgYJBgAAAA==.Blackteriaa:BAABLgAECn8UAAIJAAYJ/RNCmgBFAQAJAAYJ/RNCmgBFAQAAAA==.Blacrapumzel:BAAALgAECgMJAwAAAA==.Blakwolf:BAAALgAFFAEJAQAAAA==.Blankis:BAAALgADCgYJCQAAAA==.Blastoize:BAAALgAECgQJCAAAAA==.Blizther:BAAALgADCgIJAgAAAA==.Bloodh:BAAALgAECgUJCQAAAA==.Bloodyz:BAAALgAECgMJBAAAAA==.Bls:BAAALgADCgMJAwAAAA==.',
Bo='Boijf:BAAALgADCgEJAQAAAA==.Boladomal:BAAALgAECgQJBQAAAA==.Bolt:BAAALgADCgcJBwAAAA==.Bones:BAAALgAECgEJAQAAAA==.Boromy:BAAALgAECgcJDQAAAA==.Boruck:BAAALgAECgIJAwAAAA==.',
Br='Braandom:BAAALgAECgcJEAAAAA==.Bradan:BAABLgAECn8eAAITAAgJURWcKgAOAgATAAgJURWcKgAOAgAAAA==.Braeon:BAAALgADCgcJCQAAAA==.Brandomm:BAAALgAECgYJDwAAAA==.Branmir:BAAALgAECgMJBgAAAA==.Brazilerinha:BAAALgAECgUJBwAAAA==.Bridda:BAAALgAECggJEAAAAA==.Brinkst:BAAALgAFFAEJAgAAAA==.Brolho:BAAALgADCgEJAQAAAA==.Brusque:BAAALgAECgcJCgAAAA==.Bruzapaladin:BAAALgADCgUJBQAAAA==.',
Bt='Btrcaotics:BAAALgAECgIJCAAAAA==.Btrguard:BAAALgAECgIJAgAAAA==.',
Bu='Buddinha:BAAALgAECgQJBgAAAA==.Buddyxa:BAAALgAECgEJAQAAAA==.',
['Bé']='Béto:BAACLgAFFH8HAAIKAAIJoyDCHQCnAAAKAAIJoyDCHQCnAAAuAAQKfxYAAgoACQlfHRgMAPoCAAoACQlfHRgMAPoCAAAA.',
['Bí']='Bíbs:BAABLgAECn8VAAIBAAgJkRPtVgCfAQABAAgJkRPtVgCfAQAAAA==.',
Ca='Cabanagé:BAAALgAECgUJBwAAAA==.Cabeludometa:BAAALgAECgYJDAAAAA==.Cabodecobre:BAAALgAECgUJCwAAAA==.Cainmarko:BAAALgAECgYJEAAAAA==.Caiowisk:BAABLgAECn8eAAMPAAgJNgonjQAgAQAPAAgJSQcnjQAgAQAOAAMJZxA5LQBjAAAAAA==.Calir:BAAALgADCgYJFgAAAA==.Calçadora:BAACLgAFFH8GAAIUAAIJYxXDKACSAAAUAAIJYxXDKACSAAAuAAQKf0EAAhQACQmqIbcFAMoCABQACQmqIbcFAMoCAAAA.Caquinha:BAAALgAECgEJAQAAAA==.Cardrok:BAAALgADCgEJAQAAAA==.Caridosa:BAAALgADCgUJBQAAAA==.Carnius:BAACLgAFFH8OAAMVAAMJmhUKHgCoAAAVAAMJmhUKHgCoAAANAAEJDAWASAAzAAAuAAQKf0QABBUACAlHHmYRANQBABUACAkhHWYRANQBABMAAgm6IA6UAEoAAA0AAQkPHPduAEMAAAAA.Casipala:BAAALgAECgIJAgAAAA==.Casuall:BAAALgAECgcJBwAAAA==.Cataclysm:BAAALgAECgMJBAAAAA==.Catalango:BAAALgAECgQJCwAAAA==.Catapas:BAAALgAECgEJAQAAAA==.Catapita:BAAALgAECgIJAgAAAA==.Catapó:BAABLgAECn8UAAMPAAgJcxZocgBVAQAPAAgJcxZocgBVAQAOAAEJjQziQgAoAAAAAA==.Catapózão:BAABLgAECn8zAAIFAAkJniDHBgBLAwAFAAkJniDHBgBLAwAAAA==.Catü:BAAALgAECgEJAQAAAA==.Cavernus:BAAALgADCgMJAwAAAA==.Caves:BAAALgADCgIJAgAAAA==.Caveston:BAAALgADCgUJCgAAAA==.',
Cb='Cbestabr:BAAALgADCgYJBgAAAA==.',
Ch='Chamadmordor:BAAALgAECgMJBQAAAA==.Charats:BAAALgADCgYJDQAAAA==.Charterine:BAAALgADCgYJBgAAAA==.Chaya:BAAALgADCgUJBQAAAA==.Chicknorris:BAAALgADCgUJBQAAAA==.Chifrudaxl:BAAALgAECgMJAwAAAA==.Chrisjks:BAAALgADCgYJCgAAAA==.',
Ci='Cindyn:BAAALgAECgEJAQAAAA==.',
Cl='Clared:BAAALgADCgEJAQAAAA==.Clarkcrente:BAAALgADCgYJBgABLgAECgMJAwAEAAAAAA==.Clebeya:BAAALgADCgQJBAAAAA==.Clebsona:BAAALgAECgIJAgAAAA==.Climps:BAABLgAECn8WAAIBAAgJRRdwPQDrAQABAAgJRRdwPQDrAQAAAA==.',
Co='Cobyx:BAAALgADCgcJDAAAAA==.Cocaferoz:BAAALgADCgEJAQAAAA==.Coffeeaddict:BAAALgADCgMJAwAAAA==.Colugo:BAAALgADCgIJAgAAAA==.Coriisco:BAAALgADCgIJAgAAAA==.Corollaxei:BAABLgAECn83AAQWAAkJsxf1CwAYAgAWAAkJsxf1CwAYAgAXAAYJsQnrSAAHAQAYAAEJWAw2JgAyAAAAAA==.Cosculluela:BAAALgADCgUJBwAAAA==.Cosmuh:BAAALgAECgUJBQAAAA==.Cotori:BAAALgAECgEJAQAAAA==.',
Cr='Crauwlinhu:BAAALgAECgMJBgAAAA==.Cretaceous:BAAALgADCgEJAQAAAA==.Creuzapriest:BAAALgAECgEJAQAAAA==.Cristïe:BAAALgAECgUJBQAAAA==.Crookedyoung:BAAALgAECgEJAwABLgAECgcJEAAEAAAAAA==.Cruzade:BAABLgAECn8VAAMIAAcJXxDCIwD3AAAIAAYJwBDCIwD3AAADAAYJdw9N7ADPAAABLgAFFAQJCwABALELAA==.Cröwllëy:BAACLgAFFH8JAAMQAAMJiw3EqADLAAAQAAMJiw3EqADLAAAZAAEJZAg1FQA4AAAuAAQKfyMAAhAACAnZFxpFAPMBABAACAnZFxpFAPMBAAAA.',
Cu='Cubatao:BAABLgAECn8UAAIBAAYJUxTshwAuAQABAAYJUxTshwAuAQAAAA==.Cucaracha:BAABLgAECn8YAAIPAAYJVBaYcABZAQAPAAYJVBaYcABZAQAAAA==.',
['Cä']='Cärtrz:BAAALgADCgEJAQAAAA==.',
Da='Dahaka:BAAALgADCgEJAQAAAA==.Dahhak:BAAALgAECgUJCwAAAA==.Dakhgagul:BAAALgADCgUJBQAAAA==.Dakshayani:BAAALgAECgQJBQAAAA==.Dalaigalds:BAAALgAECgEJAQAAAA==.Danielbrz:BAAALgAECgUJBwAAAA==.Daniellpvp:BAAALgADCgEJAQAAAA==.Danygatuxa:BAAALgAECgUJDQAAAA==.Daree:BAAALgAECgEJAQAAAA==.Darkenes:BAAALgAECgEJAQAAAA==.Darkinmt:BAAALgADCgcJCAAAAA==.Darknesstk:BAAALgAECgYJEAAAAA==.Darkowllskul:BAAALgAECgQJCAABLgAECgYJEgAEAAAAAA==.Darksiderptc:BAAALgADCgcJDwAAAA==.Darthmansur:BAAALgAFFAIJBAAAAA==.Dasmithy:BAAALgAECgEJAQAAAA==.',
De='Deadvi:BAABLgAECn8YAAIaAAgJXh02DQA7AgAaAAgJXh02DQA7AgAAAA==.Deadziin:BAABLgAECn8fAAMbAAgJSAtfLwAkAQAbAAcJ6AxfLwAkAQAcAAcJTAOIFwC7AAAAAA==.Deathbringër:BAAALgAECgEJAgAAAA==.Deathheav:BAAALgADCgQJBAAAAA==.Deathivy:BAAALgAECgQJBgAAAA==.Deathmäsk:BAAALgADCgcJBwAAAA==.Defensivepls:BAAALgAECgYJBQAAAA==.Demetrix:BAAALgADCgkJCgAAAA==.Demonphantom:BAAALgAECgUJBQAAAA==.Dennyam:BAAALgAECgYJCQAAAA==.Derothey:BAABLgAECn8pAAIJAAgJYBY7WgDPAQAJAAgJYBY7WgDPAQAAAA==.Deservis:BAAALgADCgYJBgAAAA==.Deulorem:BAACLgAFFH8PAAIdAAQJih5BEABRAQAdAAQJih5BEABRAQAuAAQKfz0AAh0ACQmBIxMCAIsDAB0ACQmBIxMCAIsDAAAA.Devilblade:BAABLgAECn8RAAIeAAgJXgmljwACAQAeAAgJXgmljwACAQAAAA==.',
Di='Diabolynn:BAAALgAECgcJEwAAAA==.Digipatrocin:BAAALgAECgEJAQAAAA==.',
Dk='Dkatraia:BAAALgAECgMJBQAAAA==.',
Dn='Dngfafinir:BAAALgAFFAIJAgABLgAFFAUJDAADAFgXAA==.Dnghidan:BAACLgAFFH8MAAIDAAUJWBe2RAAiAQADAAUJWBe2RAAiAQAuAAQKfygAAgMACQmrHvohAKICAAMACQmrHvohAKICAAAA.Dngpain:BAAALgAECgcJEQABLgAFFAUJDAADAFgXAA==.Dngtobi:BAAALgAECgUJCQABLgAFFAUJDAADAFgXAA==.',
Do='Dollynhø:BAABLgAECn8nAAIfAAkJFSCDBgDjAgAfAAkJFSCDBgDjAgAAAA==.Donyed:BAAALgAECgUJDAAAAA==.Doomsman:BAAALgADCgUJBQAAAA==.Dottado:BAAALgADCgcJCgAAAA==.',
Dr='Drackah:BAAALgADCgcJBwAAAA==.Draconían:BAAALgAECgEJBwAAAA==.Dracón:BAAALgAECgYJDAAAAA==.Draigo:BAAALgAECgIJAgAAAA==.Dreykar:BAABLgAECn8uAAMeAAkJfBi9IwBBAgAeAAkJfBi9IwBBAgAgAAEJ2BxSLQBNAAAAAA==.Drogorn:BAAALgAECgUJDQAAAA==.Druidaezeki:BAAALgAECgIJAgAAAA==.Druidjm:BAAALgADCgMJAwAAAA==.Druvannar:BAAALgADCgEJAQAAAA==.Dröwränger:BAAALgADCgYJCwAAAA==.',
Du='Dultrasenegl:BAABLgAECn8lAAIBAAYJAA3yZQA2AQABAAYJAA3yZQA2AQAAAA==.Dunois:BAAALgAECgIJBgABLgAECgUJCwAEAAAAAA==.Duunyangel:BAAALgADCgIJAgAAAA==.',
['Dä']='Dähäkä:BAABLgAECn8dAAIDAAkJJBtSJAB0AgADAAkJJBtSJAB0AgAAAA==.',
Ed='Edven:BAACLgAFFH8TAAMWAAMJTAOJJAB5AAAWAAMJTAOJJAB5AAAXAAEJ4QFsMQAhAAAuAAQKfyEAAhYABgnKDMYlAEgBABYABgnKDMYlAEgBAAAA.',
Ei='Eini:BAAALgAECgEJAgAAAA==.',
El='Elbermt:BAAALgAECgEJAQAAAA==.Elbruxão:BAAALgAECgEJAQAAAA==.Eldrick:BAAALgADCgUJCAAAAA==.Eldros:BAAALgAECgYJCAAAAA==.Elementais:BAABLgAECn8eAAIKAAcJDw/JUABvAQAKAAcJDw/JUABvAQAAAA==.Elgado:BAAALgAECgEJAwAAAA==.Elgatadexota:BAAALgADCgkJCgAAAA==.Eliksir:BAAALgAECgUJBQAAAA==.Ellanor:BAABLgAECn8dAAIJAAgJ+hifVQDcAQAJAAgJ+hifVQDcAQAAAA==.Ellocopere:BAAALgAECgEJAQAAAA==.Elruth:BAAALgADCggJCAABLgAFFAQJDwAdAIoeAA==.Eltão:BAAALgAECgEJAwAAAA==.Elunah:BAAALgADCgQJBAAAAA==.Elwindor:BAAALgAECgEJAQAAAA==.Elyind:BAAALgADCgYJBwAAAA==.Elyn:BAAALgAECgUJEQAAAA==.',
Em='Emmymm:BAAALgAECgEJAQAAAA==.',
En='Endeavour:BAAALgADCgEJAQAAAA==.Enegadiel:BAABLgAECn8tAAIDAAcJdBicDgAHAQADAAcJdBicDgAHAQAAAA==.Enoia:BAAALgADCgcJDQAAAA==.',
Eq='Equidnah:BAAALgAECgIJAgAAAA==.',
Er='Erickya:BAAALgAECggJEgAAAA==.Ervadocè:BAABLgAECn8ZAAIGAAYJwhiWNQBBAQAGAAYJwhiWNQBBAQAAAA==.Ervelino:BAAALgAECgMJBAAAAA==.Eryz:BAAALgAECgMJBQAAAA==.',
Es='Esmeraldth:BAAALgAECgEJAQAAAA==.Esruc:BAAALgAECgEJAQAAAA==.Estrogosbald:BAABLgAECn8ZAAIhAAgJMQzHBgBNAQAhAAgJMQzHBgBNAQAAAA==.',
Eu='Euteinvoco:BAAALgAECgIJAgABLgAFFAEJAgAEAAAAAA==.',
Ev='Evely:BAABLgAECn83AAMiAAgJKh6cAAANAgAiAAgJ0hucAAANAgABAAQJ4R1QDwAMAQAAAA==.',
Ex='Exarch:BAACLgAFFH8NAAIUAAQJaRQfFAArAQAUAAQJaRQfFAArAQAuAAQKfysAAhQACQm/IYQDAP4CABQACQm/IYQDAP4CAAAA.',
Fa='Faengar:BAAALgAECgUJCAAAAA==.Falcondk:BAAALgAECgEJAQAAAA==.Falconess:BAAALgADCgEJAQAAAA==.Falkorr:BAAALgAECgEJAQAAAA==.Fandria:BAAALgADCgQJBAAAAA==.',
Fe='Feathria:BAAALgAECgMJAwAAAA==.Felenus:BAAALgAECgEJAQAAAA==.Felipebritoo:BAAALgAECgMJBgABLgAECgYJEgAEAAAAAA==.Fenrirsp:BAABLgAECn8XAAMjAAgJcyGKGwDoAQAjAAYJpyGKGwDoAQAkAAQJxxrLNQA+AQAAAA==.Ferdruiid:BAAALgADCgkJEwAAAA==.Feropudo:BAAALgADCgkJDgAAAA==.Ferrarig:BAAALgAECgEJBQAAAA==.',
Fi='Figy:BAAALgAECgQJBAAAAA==.Filixy:BAAALgADCgYJBgAAAA==.',
Fl='Flemma:BAABLgAECn8mAAIWAAgJ5Q+MAQBPAQAWAAgJ5Q+MAQBPAQAAAA==.Flexer:BAAALgAECgIJAgAAAA==.Flores:BAAALgADCgMJBgAAAA==.Floridastyle:BAABLgAECn8fAAIkAAUJTxa5NwA0AQAkAAUJTxa5NwA0AQAAAA==.Flux:BAAALgAECgUJCQAAAA==.',
Fo='Foguerosa:BAACLgAFFH8JAAMJAAMJpRyQLwD4AAAJAAMJpRyQLwD4AAAlAAEJggBqCAAxAAAuAAQKfxYAAgkACAlpIVREAGsCAAkACAlpIVREAGsCAAAA.Folghunthir:BAAALgADCgQJBAAAAA==.Fortis:BAAALgADCgUJBQAAAA==.',
Fr='Frankkquini:BAAALgADCgYJEgAAAA==.Friodokrl:BAACLgAFFH8JAAIQAAMJIw4ppwDNAAAQAAMJIw4ppwDNAAAuAAQKfzYAAxoACQkHHj4PABcCABoACQkuGz4PABcCABAACAkdGuJEAPQBAAAA.Fritzgerhart:BAAALgAECgEJAQAAAA==.Frostkller:BAAALgADCgIJAgAAAA==.Frostmhaw:BAAALgADCgUJBQAAAA==.Frostreaper:BAAALgAECgQJBgAAAA==.',
Fu='Fubukiofhell:BAACLgAFFH8JAAIJAAMJ6xfSKQDcAAAJAAMJ6xfSKQDcAAAuAAQKfxoAAgkACAnVGVlBABgCAAkACAnVGVlBABgCAAAA.Fuginzao:BAAALgAECgEJAQAAAA==.Furtacor:BAAALgAECgEJAgAAAA==.Furyarh:BAAALgAECgMJAwAAAA==.',
['Fö']='Föxhüntër:BAAALgAECgIJAgAAAA==.',
Ga='Gaarpo:BAAALgADCgIJAgAAAA==.Gabana:BAAALgADCgQJBAAAAA==.Gabdobbuh:BAAALgAECgUJCAAAAA==.Gabn:BAAALgAECgMJBgAAAA==.Gabricia:BAAALgADCgIJAgAAAA==.Gafgar:BAAALgADCgUJCQAAAA==.Gaila:BAAALgAECgIJBgAAAA==.Galduin:BAACLgAFFH8HAAITAAMJ5wy/OQDMAAATAAMJ5wy/OQDMAAAuAAQKfzQAAhMACQncGbYYACgCABMACQncGbYYACgCAAAA.',
Ge='Gedexx:BAAALgAECgMJAgAAAA==.Geduntruppa:BAAALgAECgYJBgAAAA==.Gemerover:BAAALgAECgIJAgAAAA==.Gentioiroh:BAAALgAECgQJBAAAAA==.',
Gh='Ghorderp:BAAALgADCgcJDAAAAA==.Ghosstt:BAAALgAECgEJAgAAAA==.Ghoulrozon:BAAALgADCgYJBgAAAA==.',
Gi='Giovannapala:BAABLgAECn8aAAIDAAgJiQ73oAA2AQADAAgJiQ73oAA2AQAAAA==.Giovannasham:BAAALgAECgEJAwAAAA==.Giripoca:BAAALgAECgQJCQAAAA==.',
Gl='Gladsmonge:BAABLgAECn8pAAImAAcJ3h8EFgBqAgAmAAcJ3h8EFgBqAgAAAA==.Glorcckk:BAAALgAECgUJCgAAAA==.',
Gn='Gnomagga:BAAALgAECgcJEAABLgAECggJNgAIAB8cAA==.Gnomohabe:BAAALgADCgQJBgAAAA==.',
Go='Goddofwarr:BAAALgADCggJEQAAAA==.Gonb:BAAALgADCgUJBQAAAA==.Goueki:BAABLgAECn80AAMBAAgJmBrZMAAYAgABAAgJmBrZMAAYAgAiAAIJSwEtgwA8AAAAAA==.',
Gr='Greenzle:BAAALgAECgUJBgAAAA==.Grillnborst:BAAALgADCgEJAgAAAA==.Grilonp:BAAALgADCgQJCAAAAA==.Grogath:BAAALgAECgQJCAAAAA==.Grogtixa:BAAALgAECggJCQABLgAECgkJKgALAFcWAA==.Gromoff:BAABLgAFFH8HAAIPAAIJwiREhAC9AAAPAAIJwiREhAC9AAAAAA==.Grunmonk:BAAALgADCgEJAQAAAA==.Grømmar:BAAALgADCgMJAwAAAA==.',
Gu='Gudangara:BAAALgAECgIJAgAAAA==.Gumy:BAAALgAECgEJBAAAAA==.Guztaverdead:BAAALgADCgQJBAAAAA==.',
['Gü']='Güistrong:BAAALgADCgIJAwAAAA==.',
Ha='Haakaí:BAAALgAECgUJEAAAAA==.Haandir:BAAALgAFFAEJAQAAAA==.Hackterin:BAAALgADCgYJBgAAAA==.Hadorah:BAAALgAECgUJBgAAAA==.Haelle:BAAALgAFFAEJAQAAAA==.Haerys:BAAALgAFFAEJAQAAAA==.Handhemirr:BAAALgAECgMJBAAAAA==.Haranclaw:BAAALgAECgEJAQAAAA==.Harany:BAABLgAECn8qAAMkAAgJXRe5EgBOAgAkAAgJXRe5EgBOAgAjAAYJWg2FCwCXAAAAAA==.Harrypotinho:BAABLgAECn83AAIPAAkJfhs+JwBAAgAPAAkJfhs+JwBAAgAAAA==.Harttas:BAAALgADCgUJBQAAAA==.Haunexd:BAAALgADCgMJAwAAAA==.Havenna:BAAALgAECgUJCAAAAA==.',
He='Headøhunter:BAAALgAECgEJAgAAAA==.Healgate:BAAALgAECgEJAQAAAA==.Heeythaly:BAAALgAECgEJAQAAAA==.Hegekant:BAAALgAFFAEJAQAAAA==.Helessa:BAAALgAECgEJAgAAAA==.Hellenah:BAAALgADCggJCAAAAA==.Herablack:BAAALgAFFAIJAwAAAA==.Herika:BAAALgADCgMJAwAAAA==.',
Hi='Hidenz:BAAALgAECgIJAgAAAA==.',
Ho='Hoem:BAAALgAECgMJAwAAAA==.Holand:BAAALgAECgYJDAAAAA==.Holydread:BAAALgAECgIJAgAAAA==.',
Hu='Hulig:BAACLgAFFH8GAAIDAAMJGSFMHADnAAADAAMJGSFMHADnAAAuAAQKfykAAwMACAn+H3gnAGYCAAMACAn+H3gnAGYCAAgAAQkBB+dUACcAAAAA.Hunthearthas:BAAALgAECgMJAwAAAA==.',
['Hø']='Høkulani:BAABLgAECn8dAAIJAAcJchH+iwBfAQAJAAcJchH+iwBfAQAAAA==.',
Ib='Ibrad:BAAALgAECgQJBAAAAA==.Ibuprofens:BAAALgAECgEJAQAAAA==.',
Ic='Iceyag:BAAALgAECgIJAgAAAA==.',
Ig='Igthil:BAAALgADCgYJEAAAAA==.',
Ik='Ikiam:BAAALgAECgYJDQAAAA==.Ikslawok:BAAALgAECgUJCQAAAA==.',
Il='Ileria:BAAALgAECgcJCQAAAA==.Iliriana:BAAALgAECgEJAQAAAA==.Illarion:BAAALgADCgQJBAAAAA==.Illidanos:BAABLgAECn8cAAInAAgJ/REqIAB4AQAnAAgJ/REqIAB4AQAAAA==.Illidansan:BAAALgAECgQJBQABLgAECgYJCwAEAAAAAA==.Illidris:BAAALgAECgUJBQAAAA==.Illumiinated:BAABLgAECn8UAAISAAYJiwx/RQCSAAASAAYJiwx/RQCSAAAAAA==.',
Im='Imathias:BAAALgAECgQJBAAAAA==.',
In='Incarus:BAAALgAECgcJCgAAAA==.Incognita:BAAALgAECgEJAQAAAA==.Indis:BAAALgADCgQJBgAAAA==.Infyniti:BAAALgAECgQJBAAAAA==.Interst:BAAALgAECgEJAQAAAA==.',
Ir='Irandel:BAAALgADCgUJBQAAAA==.Irion:BAAALgAECgQJBQAAAA==.',
Is='Iscalio:BAAALgAECgYJCgAAAA==.',
It='Itatchii:BAAALgAECgQJBQAAAA==.',
Iu='Iuuh:BAAALgAFFAIJAwAAAA==.',
Iv='Ivinhosilva:BAAALgADCgYJBgAAAA==.',
Ja='Jackdawnsong:BAABLgAECn8aAAIJAAgJiRqzOgAuAgAJAAgJiRqzOgAuAgAAAA==.Jaene:BAAALgADCgYJDQAAAA==.Jahuun:BAABLgAECn8aAAIDAAcJ7Q1TmwA/AQADAAcJ7Q1TmwA/AQAAAA==.Jamantoso:BAAALgAECgEJAQAAAA==.',
Je='Jeess:BAAALgADCgMJAwAAAA==.Jefflich:BAABLgAECn8iAAMQAAgJ4AqUiQBuAQAQAAgJiwmUiQBuAQAZAAEJhhJqPAAuAAAAAA==.',
Jg='Jg:BAAALgAECgUJBwABLgAECgYJDgAEAAAAAA==.',
Ji='Jinknu:BAAALgAECgIJBAAAAA==.',
Jo='Jojoadventur:BAAALgAECgEJAQAAAA==.Jotaloko:BAAALgAECgIJAgAAAA==.Jottapeg:BAAALgADCgcJAwAAAA==.',
Ju='Jubard:BAAALgADCgkJDAAAAA==.Juliamarques:BAAALgAECgMJBAAAAA==.',
['Jü']='Jüllÿe:BAAALgADCgEJAQAAAA==.',
Ka='Kaaellthas:BAAALgAECgQJDQAAAA==.Kacolux:BAAALgADCgEJAQAAAA==.Kaisaargente:BAAALgAECgEJAQAAAA==.Kakarotho:BAAALgAECgMJCQAAAA==.Kalarath:BAAALgAECgYJBgAAAA==.Kaldonios:BAAALgADCgcJEgAAAA==.Kalma:BAAALgAECgEJAQAAAA==.Kamasutram:BAAALgADCgYJCwAAAA==.Kanadriel:BAAALgAECgcJDAAAAA==.Kanarinho:BAABLgAECn80AAIFAAkJIh/2CAApAwAFAAkJIh/2CAApAwAAAA==.Karagume:BAAALgAECgMJBAAAAA==.Kardibito:BAAALgAECgcJDAAAAA==.Karmussie:BAAALgADCgEJAQAAAA==.Karmysh:BAAALgAECgMJAwAAAA==.Katari:BAAALgAECgYJCgABLgAECgkJIAACAAMfAA==.Kayanz:BAAALgADCgUJBQAAAA==.Kazandra:BAAALgADCgYJBgAAAA==.Kazhadum:BAAALgAECgEJAQAAAA==.',
Ke='Kendars:BAABLgAECn8VAAQGAAYJ0xKfSAAKAQAGAAUJJhKfSAAKAQAFAAUJFQ+5dgDzAAAHAAEJhRUFSwBDAAABLgAFFAMJBwAaALAMAA==.Keox:BAAALgADCgUJBQAAAA==.Ket:BAAALgADCgMJAwAAAA==.',
Kh='Khanmir:BAAALgAECgMJBgAAAA==.Kharon:BAAALgAECgYJBwAAAA==.Khild:BAAALgAECgYJDQAAAA==.Khonar:BAAALgADCgUJCQAAAA==.',
Ki='Killerdek:BAAALgAECgUJBQAAAA==.Killshoty:BAAALgAECgEJAgAAAA==.',
Kl='Klissera:BAAALgADCgQJBAAAAA==.Kluzlocak:BAABLgAECn8iAAIkAAYJUQz6PgAQAQAkAAYJUQz6PgAQAQAAAA==.',
Ko='Komah:BAAALgAECgEJAQAAAA==.Korav:BAAALgAECgMJCQABLgAFFAEJAQAEAAAAAA==.Korium:BAAALgADCgUJBQABLgAECgkJOAAVAFckAA==.Koruno:BAAALgADCgYJBgAAAA==.',
Kr='Krosn:BAAALgAECgEJAQAAAA==.Krozhul:BAAALgAECgcJDQAAAA==.Krypthor:BAAALgAECgEJAQAAAA==.',
Ku='Kurnous:BAAALgAECgEJAQAAAA==.Kutirenzo:BAAALgADCgUJBwAAAA==.',
['Kä']='Käew:BAAALgAECgEJAQAAAA==.',
La='Lafiel:BAAALgAECgcJEgAAAA==.Lahllis:BAAALgAECgQJBQAAAA==.Lahnara:BAAALgAECgcJEwAAAA==.Lamelo:BAAALgADCgYJBgAAAA==.Lanjelanje:BAAALgAECgQJBQAAAA==.Lanmo:BAABLgAFFH8HAAISAAIJmw8EFwBXAAASAAIJmw8EFwBXAAAAAA==.Largatixazul:BAAALgADCgUJBgAAAA==.Lataria:BAAALgADCgEJAQAAAA==.Laurea:BAAALgAECgkJEQABLgAECgkJIAACAAMfAA==.',
Le='Ledor:BAAALgAECgEJAgAAAA==.Leebron:BAAALgAECgYJDAAAAA==.Lefthalas:BAAALgAECgUJCgAAAA==.Leitchero:BAAALgAECgIJAgAAAA==.Lemaz:BAAALgAECgEJAQAAAA==.Lemonhunter:BAAALgAECgYJCgAAAA==.Leolock:BAAALgAECgEJAQAAAA==.Leonelmessi:BAAALgAFFAQJAgAAAA==.Lesco:BAAALgADCgMJAwAAAA==.',
Li='Lianele:BAAALgAECgcJDAAAAA==.Liaras:BAABLgAECn8pAAMdAAgJXBeIHgDRAQAdAAgJXBeIHgDRAQAjAAIJzABFaQAmAAAAAA==.Libertinagem:BAAALgAECgYJDQAAAA==.Lichtbaum:BAABLgAECn8nAAMFAAgJoB1aIABAAgAFAAgJoB1aIABAAgAGAAUJwxnVOAAwAQAAAA==.Lightsertrop:BAAALgADCgIJAgAAAA==.Liifecomm:BAACLgAFFH8cAAIdAAUJBxV3DgBmAQAdAAUJBxV3DgBmAQAuAAQKf0IAAh0ACQl6H0MBAEoCAB0ACQl6H0MBAEoCAAAA.Liike:BAAALgAECgcJDQAAAA==.Linestra:BAAALgADCgUJBQAAAA==.Liniak:BAAALgAECgcJEAAAAA==.Liorfield:BAAALgAECgQJBAAAAA==.Littlepurple:BAACLgAFFH8JAAIeAAMJzxJ7GwD2AAAeAAMJzxJ7GwD2AAAuAAQKfyQAAh4ACQl0HJwYAMICAB4ACQl0HJwYAMICAAAA.',
Lo='Longhai:BAAALgADCgUJCAAAAA==.Lookatmylock:BAABLgAECn8iAAMOAAYJ/xu2DAB0AQAOAAYJ/xu2DAB0AQAPAAIJmBFNHQFKAAAAAA==.Lordpain:BAAALgAECggJDgAAAA==.Lortherti:BAAALgAECgIJAgAAAA==.Lorwin:BAABLgAECn8UAAIBAAgJhBmbSgDBAQABAAgJhBmbSgDBAQAAAA==.Lotusbr:BAAALgADCgEJAQAAAA==.Louisenacioo:BAABLgAECn8UAAMWAAcJUhCMFQB0AQAWAAcJUhCMFQB0AQAXAAMJqwXgewBpAAAAAA==.Loátrak:BAAALgADCgMJAwAAAA==.',
Lu='Luanne:BAAALgADCgEJAQAAAA==.Luccablack:BAAALgAFFAEJAQAAAA==.Luccagelido:BAAALgAECgYJEAAAAA==.Lucyx:BAAALgAECgIJAgAAAA==.Luidar:BAAALgAECgQJBAAAAA==.Lukaslions:BAABLgAECn8gAAITAAkJaA8TLACkAQATAAkJaA8TLACkAQAAAA==.Lukathan:BAAALgADCgQJBAAAAA==.Lunarie:BAAALgAECgYJEwABLgAECgcJBwAEAAAAAA==.Luphoe:BAABLgAECn8nAAMFAAcJ9RzHJwAWAgAFAAcJ9RzHJwAWAgAGAAQJkw4kZACLAAAAAA==.Luthira:BAAALgAECgEJAQAAAA==.Luxanä:BAAALgAECgYJCwAAAA==.',
['Lé']='Léio:BAAALgADCgcJCAAAAA==.Léora:BAAALgADCgIJAgAAAA==.',
['Lø']='Lørdsith:BAAALgAECgYJCAABLgAFFAcJAQAEAAAAAA==.',
['Lÿ']='Lÿcans:BAAALgADCgEJAQAAAA==.Lÿcäns:BAAALgADCgMJAwAAAA==.',
Ma='Maars:BAAALgAECgEJAgAAAA==.Madagalux:BAABLgAECn8rAAIRAAgJQQr3DwBfAQARAAgJQQr3DwBfAQAAAA==.Madalenna:BAAALgAECgMJCAAAAA==.Madjack:BAAALgAECgMJAwAAAA==.Madushi:BAAALgAFFAEJAQAAAA==.Madzerø:BAAALgAECgEJBAAAAA==.Magatiun:BAAALgADCgMJBAAAAA==.Magogunt:BAABLgAECn8kAAIJAAkJMxHDVADeAQAJAAkJMxHDVADeAQAAAA==.Maguul:BAABLgAECn8ZAAIIAAgJ5hWWEQCrAQAIAAgJ5hWWEQCrAQAAAA==.Magzifeh:BAABLgAECn8UAAIBAAcJ3SAkOwDyAQABAAcJ3SAkOwDyAQAAAA==.Mahadevi:BAAALgADCgIJAgAAAA==.Mahdemon:BAAALgAECgYJCQAAAA==.Maiconhood:BAAALgAFFAEJAQAAAA==.Malaks:BAAALgADCgMJAwAAAA==.Malandrvs:BAAALgAFFAEJAwAAAA==.Maljamim:BAAALgADCgIJAgAAAA==.Mamuthwar:BAABLgAECn8ZAAMTAAcJnRgeNgDQAQATAAcJnRgeNgDQAQANAAEJMQ7ZQQA1AAAAAA==.Mandingavudu:BAAALgAECgYJBwABLgAFFAEJAQAEAAAAAA==.Manei:BAAALgAECgMJAwAAAA==.Mangalarga:BAAALgADCgEJAQAAAA==.Manmoden:BAAALgADCgUJBQABLgAFFAEJAQAEAAAAAA==.Mannaton:BAAALgAECgQJBAABLgAFFAEJAQAEAAAAAA==.Mannatur:BAABLgAECn8bAAMGAAkJ6hxoEgBDAgAGAAgJ3xtoEgBDAgASAAgJahf5EQDQAQABLgAFFAEJAQAEAAAAAA==.Manopaladino:BAAALgADCgYJBgAAAA==.Manowlo:BAAALgAECgMJAwAAAA==.Manzagon:BAAALgAECgYJCQABLgAFFAEJAQAEAAAAAA==.Marandracon:BAAALgADCgMJAwAAAA==.Marmelo:BAAALgADCgQJBAAAAA==.Marretasanta:BAABLgAECn8kAAIDAAcJCRR4jwBTAQADAAcJCRR4jwBTAQAAAA==.Maruterrestr:BAAALgAECgMJAgAAAA==.Marù:BAAALgAECgYJCwAAAA==.Marúh:BAACLgAFFH8SAAIKAAUJPRjaIgBkAQAKAAUJPRjaIgBkAQAuAAQKfykAAgoACQmQIMQFABYDAAoACQmQIMQFABYDAAAA.Matedellmor:BAAALgAECgEJAQAAAA==.Matroná:BAAALgADCggJBwAAAA==.Maxmorf:BAAALgADCgUJBQAAAA==.Mayarabr:BAAALgAFFAEJAQAAAA==.Mazeratos:BAAALgAECgMJBQAAAA==.',
Mc='Mcorelhao:BAAALgADCgEJAQAAAA==.',
Me='Medoza:BAAALgAECgQJBgAAAA==.Megrezz:BAAALgAECgEJAQAAAA==.Mehiel:BAAALgAECgEJAQAAAA==.Mekihlvshtak:BAAALgAECgYJBwAAAA==.Melblaw:BAAALgAECgEJAwAAAA==.Meliøðas:BAAALgADCgEJAQAAAA==.Mendingu:BAABLgAECn8YAAMNAAgJAhwEGwCDAQATAAgJRxgYKAAdAgANAAQJ/CAEGwCDAQAAAA==.Mercenarybr:BAAALgAECgEJAgAAAA==.Merumim:BAAALgAECgYJCwAAAA==.Metalgirl:BAAALgADCgYJCwAAAA==.Methamorfo:BAAALgADCggJCQAAAA==.',
Mi='Midrão:BAACLgAFFH8GAAIDAAMJhgQmRwBSAAADAAMJhgQmRwBSAAAuAAQKfxgAAwMACAn1EKCAAG4BAAMACAn1EKCAAG4BAAgAAgkqBTZPADMAAAAA.Miisuky:BAAALgAECgEJAQAAAA==.Mikasaackerr:BAAALgAECgEJAgAAAA==.Milczarek:BAAALgAECgEJAwAAAA==.Mindlocker:BAABLgAECn8dAAIPAAcJMwmnkwAUAQAPAAcJMwmnkwAUAQAAAA==.Minorus:BAAALgAFFAIJBAAAAA==.Mirager:BAAALgAECgQJBAAAAA==.Mistifs:BAABLgAECn8pAAImAAgJ5R1rDwCsAgAmAAgJ5R1rDwCsAgAAAA==.Miticamais:BAAALgAECgQJBQAAAA==.',
Mo='Modogz:BAAALgADCgYJBgAAAA==.Momongadk:BAAALgADCgcJBwAAAA==.Monkeydking:BAAALgADCgUJBQAAAA==.Morania:BAABLgAECn8XAAIOAAgJUwbrFwDiAAAOAAgJUwbrFwDiAAAAAA==.Mordekais:BAAALgAFFAIJAgAAAA==.Morganne:BAAALgAECgEJAQAAAA==.Morinami:BAAALgAECgQJBwAAAA==.Moriyama:BAABLgAECn8rAAMFAAkJOR0wIQA+AgAFAAgJbxwwIQA+AgAGAAIJExJzbABxAAAAAA==.Morphez:BAAALgAECgEJAwABLgAFFAEJAQAEAAAAAA==.Morphisz:BAAALgAFFAEJAQAAAA==.Morphiszs:BAAALgAECgMJBQABLgAFFAEJAQAEAAAAAA==.Morphizs:BAAALgAECgEJBQABLgAFFAEJAQAEAAAAAA==.Mortesan:BAAALgAECgEJAQABLgAECgYJCwAEAAAAAA==.',
Mp='Mpastor:BAAALgADCgUJBQAAAA==.',
Mu='Muca:BAAALgADCgEJAQAAAA==.Muho:BAAALgADCgEJAQAAAA==.Mukonha:BAABLgAECn8jAAIPAAcJeA4RjQAgAQAPAAcJeA4RjQAgAQAAAA==.',
My='Myzukim:BAAALgADCgYJBQAAAA==.',
['Mã']='Mãoleves:BAAALgADCgEJAQAAAA==.',
['Må']='Måximus:BAAALgAECgUJCQAAAA==.',
['Mü']='Müller:BAAALgADCgEJAQABLgAECgcJEAAEAAAAAA==.',
Na='Naeryndam:BAAALgADCgEJAQAAAA==.Namyara:BAAALgAECgEJAQAAAA==.Narutowow:BAAALgADCgMJAwAAAA==.Natcmd:BAAALgADCggJLAAAAA==.Nathilell:BAAALgADCgIJAgAAAA==.Naturezo:BAAALgAECgcJEwAAAA==.Navira:BAAALgAECgEJAQAAAA==.Nayanna:BAAALgADCgcJDQAAAA==.Nazzd:BAAALgAECgQJBAABLgAFFAIJAgAEAAAAAA==.',
Ne='Nedy:BAAALgADCgMJAwAAAA==.Negblack:BAACLgAFFH8IAAIBAAMJswodawDOAAABAAMJswodawDOAAAuAAQKfxQAAgEABwlLDX+AAD4BAAEABwlLDX+AAD4BAAAA.Neggi:BAAALgAECgUJBwAAAA==.Nemesysy:BAAALgAECgMJAwAAAA==.Nerphien:BAAALgADCgUJBQAAAA==.Nesktpally:BAAALgAECgcJCAAAAA==.Netbrood:BAAALgADCgUJBgABLgAECgUJBwAEAAAAAA==.Netbrother:BAAALgAECgUJBwAAAA==.Nethdorai:BAAALgADCgQJBAAAAA==.Netherbane:BAABLgAECn82AAMNAAkJvRvKDQAMAgANAAkJvRvKDQAMAgATAAIJGQ9JpAAxAAAAAA==.Nezuko:BAAALgAECgUJBQABLgAECgkJNwAPAH4bAA==.',
Ni='Niar:BAAALgAECgQJBQAAAA==.Nightmære:BAAALgAECgQJCwAAAA==.Nikelina:BAAALgAECgEJAQAAAA==.Nikelok:BAABLgAECn8ZAAIPAAcJfgfrogD6AAAPAAcJfgfrogD6AAAAAA==.Ninfador:BAABLgAECn8eAAIkAAYJgxerMQBVAQAkAAYJgxerMQBVAQAAAA==.Ninpus:BAAALgAECgMJAwAAAA==.',
No='Noobmasteer:BAAALgADCgIJAgAAAA==.Nooneknow:BAACLgAFFH8HAAIQAAQJTBUOlADkAAAQAAQJTBUOlADkAAAuAAQKfzkAAhAACQlUIUYWAMECABAACQlUIUYWAMECAAAA.Nosios:BAAALgAECgYJBgAAAA==.Nosrede:BAAALgAECgEJAQAAAA==.Notz:BAAALgADCgMJBAAAAA==.',
Nu='Nucciwarrior:BAAALgAECgUJCAAAAA==.Nuccixama:BAAALgAECgcJCQAAAA==.',
Ny='Nyde:BAAALgAECgMJAwAAAA==.',
['Né']='Néymar:BAAALgAECgIJAgABLgAECgkJGwAQABwQAA==.',
['Nø']='Nøar:BAAALgADCgIJAgAAAA==.',
Oa='Oakshlar:BAAALgAFFAEJAgAAAA==.',
Oc='Ocelaris:BAAALgAECgEJAgAAAA==.',
Oh='Ohlu:BAAALgAECgYJCQAAAA==.Ohluh:BAAALgAECgcJDQAAAA==.',
Or='Ormagh:BAAALgADCgYJBgAAAA==.Oryana:BAAALgAECgcJCAAAAA==.Oríon:BAAALgADCgIJAgAAAA==.',
Ot='Otton:BAABLgAECn8qAAIDAAkJagktuwAPAQADAAkJagktuwAPAQAAAA==.',
Ov='Overnigth:BAAALgADCgIJAgAAAA==.Overwalker:BAAALgAECgEJAgAAAA==.Ovosemdente:BAAALgADCgEJAQAAAA==.',
Ow='Owllskull:BAAALgAECgYJEgAAAA==.',
Oz='Ozovo:BAAALgAECgcJEgAAAA==.',
Pa='Pacoka:BAAALgADCgQJBQAAAA==.Padrafferty:BAAALgADCgcJBwAAAA==.Paidesanto:BAABLgAECn8WAAQRAAcJyhAYGwDlAAARAAYJKg8YGwDlAAAPAAYJMgt+0gCwAAAOAAMJ5RGTRgCcAAAAAA==.Paidesantox:BAABLgAECn8YAAIGAAcJRAkIRQD4AAAGAAcJRAkIRQD4AAABLgAFFAMJBwATAOcMAA==.Paidocharles:BAAALgAECgIJBQAAAA==.Paimax:BAAALgAECgEJAQAAAA==.Paladinokun:BAAALgAECgYJCwAAAA==.Palanis:BAAALgAECgcJBwAAAA==.Palazarta:BAABLgAECn8XAAIDAAcJBAqRvgAKAQADAAcJBAqRvgAKAQAAAA==.Pandadruid:BAAALgADCgMJAwAAAA==.Pandavoli:BAAALgAECgUJDAAAAA==.Pangolinho:BAAALgAECgQJBgAAAA==.Panky:BAAALgAECgQJBAAAAA==.Panquecudo:BAAALgADCgIJAgAAAA==.',
Pd='Pdois:BAAALgADCgMJAwAAAA==.',
Pe='Pesscador:BAAALgAECgMJAwAAAA==.Petrolesk:BAAALgAECgYJEwAAAA==.',
Pi='Piriguetee:BAAALgADCgEJAQAAAA==.Pirro:BAAALgAECgEJAQAAAA==.Pisadinha:BAAALgADCgcJBwAAAA==.',
Pk='Pkzimn:BAAALgADCgUJBQAAAA==.',
Pl='Playsson:BAAALgAECgYJEwAAAA==.Plottwist:BAAALgADCgcJDwABLgAECgkJQgAQAPobAA==.',
Po='Pogonus:BAAALgADCgIJAgAAAA==.Pontocego:BAAALgAECgQJBAAAAA==.Pororocaa:BAAALgAECgQJCAAAAA==.Posturado:BAAALgADCgEJAQAAAA==.Powerworth:BAAALgAECgEJAQAAAA==.',
Pr='Pravios:BAAALgAECggJDgAAAA==.Priestkill:BAAALgADCgcJCQAAAA==.Prikithon:BAAALgAECgEJAQAAAA==.Primewolf:BAAALgAECgMJAwAAAA==.',
Ps='Psicomanic:BAAALgADCgMJAwAAAA==.',
Pt='Pterodactilo:BAAALgAECgYJAQAAAA==.',
Pu='Puherito:BAAALgAECgUJDAAAAA==.Purgas:BAAALgAFFAEJAQAAAA==.Purifc:BAAALgAECgEJAQAAAA==.',
Qu='Quartohokage:BAAALgADCgEJAQAAAA==.Quinthalam:BAAALgADCgMJAwAAAA==.',
Ra='Rafac:BAAALgAECgEJAgABLgAFFAEJAQAEAAAAAA==.Rafazinho:BAAALgADCgQJBAAAAA==.Ramyna:BAAALgAECgMJBQAAAA==.Ramyra:BAAALgADCgcJDQAAAA==.Raphaeldh:BAAALgAECgEJAgAAAA==.Raphahunterr:BAAALgADCgEJAQAAAA==.Raposa:BAAALgADCgEJAQAAAA==.Raposinha:BAAALgADCgMJAwAAAA==.Rarkway:BAAALgAECgcJCwAAAA==.Ravenblak:BAAALgADCgMJAwAAAA==.Rayanne:BAAALgADCgYJBgAAAA==.Raycujoh:BAAALgADCgIJAgAAAA==.',
Re='Reckfull:BAAALgAECgYJBgAAAA==.Regininha:BAAALgAECgEJAQAAAA==.Reloumifrend:BAAALgAECgcJCgAAAA==.Rendros:BAAALgADCgUJBQAAAA==.',
Rh='Rhaegaar:BAAALgAECgcJDQAAAA==.Rhanideri:BAAALgADCgEJAQAAAA==.Rhodinius:BAAALgAECgMJCAAAAA==.',
Ri='Rivotreel:BAAALgADCgQJBAAAAA==.',
Ro='Robeerth:BAACLgAFFH8LAAIBAAQJsQsEGAAaAQABAAQJsQsEGAAaAQAuAAQKfxcABAEACQnhFhovACACAAEACQnhFhovACACABQAAQnnEt1ZAEYAACIAAQkAAENJAAAAAAAA.Rochera:BAAALgAECgEJAQAAAA==.Rokhanar:BAAALgAECgUJCwAAAA==.',
Ru='Rudemonster:BAAALgAECgEJAQAAAA==.Ruhtarr:BAAALgADCgEJAQAAAA==.Runak:BAAALgADCgEJAQAAAA==.',
Ry='Ryukato:BAAALgAECgQJBQAAAA==.',
Sa='Saek:BAAALgAECgcJEgAAAA==.Saelor:BAAALgAECgQJCAAAAA==.Sakurachan:BAAALgADCgUJBQAAAA==.Salaciel:BAAALgAECgMJAwAAAA==.Sanderclone:BAAALgAECgEJAQAAAA==.Sanguenafaca:BAAALgADCgYJCgAAAA==.Santiss:BAABLgAECn8WAAIDAAYJDhWZqQApAQADAAYJDhWZqQApAQAAAA==.Santorini:BAAALgAECgcJDQAAAA==.Saphirot:BAAALgADCgUJBQAAAA==.Saphis:BAAALgADCgEJAQAAAA==.Sardado:BAAALgAECgEJAQAAAA==.Sardron:BAAALgAECgEJAQAAAA==.Satanaris:BAAALgADCgEJAQAAAA==.',
Sc='Scanorr:BAAALgAECgYJDQAAAA==.Scheffers:BAABLgAECn8YAAIjAAYJwRMsNgA9AQAjAAYJwRMsNgA9AQAAAA==.',
Se='Selah:BAAALgADCgQJBgAAAA==.Selver:BAAALgAECgcJCAABLgAFFAkJIgAjAMwXAA==.Selüne:BAAALgAECgcJDQAAAA==.Sephora:BAAALgAECgYJCwABLgAECggJKQAdAFwXAA==.Sevagoth:BAAALgAECggJDQAAAA==.',
Sh='Shadowlock:BAAALgADCgIJAQABLgAECgYJFAAeAN8UAA==.Shadowmornac:BAAALgAECgMJBgAAAA==.Shallkiller:BAAALgADCgIJBAAAAA==.Shamanica:BAAALgAECgEJAgAAAA==.Shamateus:BAAALgADCggJEwAAAA==.Shasuna:BAAALgADCgIJAgAAAA==.Shaunnun:BAAALgADCgEJAQAAAA==.Shenloong:BAAALgADCgYJBgAAAA==.Shieldhonor:BAAALgADCgUJBQAAAA==.Shinnók:BAAALgAECgIJAgAAAA==.Shiíro:BAAALgAFFAIJBAABLgAFFAUJEwADABAkAA==.Shuruupita:BAAALgAECgEJAgAAAA==.Shynato:BAAALgADCgEJAQAAAA==.Shynock:BAAALgADCgEJAQAAAA==.Shyriull:BAAALgAECgEJAQAAAA==.Shyzuno:BAAALgADCgQJBAAAAA==.Shãka:BAAALgADCgMJAwAAAA==.',
Si='Siladriel:BAAALgADCgMJAwAAAA==.Silfirrion:BAAALgADCgEJAQABLgAFFAIJBgARAMkYAA==.Silvanna:BAAALgAECgYJEAAAAA==.Silvao:BAAALgADCgIJBAAAAA==.Sirgonzo:BAABLgAECn8XAAIDAAkJtxdwPgAMAgADAAkJtxdwPgAMAgAAAA==.',
Sk='Skullexus:BAAALgAECgMJBAAAAA==.Skunkbr:BAAALgADCgEJAQAAAA==.',
Sl='Sleepychety:BAAALgAECgUJBgAAAA==.Slowsmoke:BAAALgADCgYJBwAAAA==.Slyfer:BAABLgAFFH8GAAIBAAIJwRQ4gACYAAABAAIJwRQ4gACYAAAAAA==.',
Sn='Snatzz:BAAALgADCgMJAgAAAA==.',
So='Soggoth:BAAALgADCgkJCQAAAA==.Solk:BAAALgAECgMJBgAAAA==.Sontarfury:BAAALgAECgEJAQAAAA==.Soray:BAAALgAECgUJBgAAAA==.Sorim:BAABLgAECn8rAAIFAAkJLhorHABlAgAFAAkJLhorHABlAgAAAA==.Soryan:BAABLgAECn8tAAMFAAkJxhTTLwDkAQAFAAkJxhTTLwDkAQAGAAUJ+g3yUADKAAAAAA==.Soulassassin:BAAALgADCgIJAwAAAA==.Soulhell:BAABLgAECn8cAAIkAAYJaxQbNQBBAQAkAAYJaxQbNQBBAQAAAA==.',
Sp='Spartanlofs:BAAALgADCgcJEQAAAA==.Spawndeath:BAAALgADCgEJAQAAAA==.Spezia:BAAALgAECgQJBQAAAA==.',
Sr='Srluizz:BAAALgAECgIJAgAAAA==.',
Ss='Ssushii:BAAALgAECgEJAQAAAA==.',
St='Staffkiller:BAABLgAECn8YAAIJAAgJUAaeEgDgAAAJAAgJUAaeEgDgAAAAAA==.Stellån:BAAALgADCgcJCAAAAA==.Stigmata:BAAALgAECgEJAgAAAA==.Stixlightmix:BAABLgAFFH8FAAMfAAMJ5hFXLgCPAAAfAAIJORhXLgCPAAAoAAEJQAWZXwAxAAAAAA==.Stixmixdk:BAABLgAFFH8FAAIaAAMJIhaCMgByAAAaAAMJIhaCMgByAAAAAA==.Stixmixwarr:BAAALgAFFAYJAQAAAA==.Straz:BAAALgADCgQJBAAAAA==.Strongman:BAAALgAECgYJBgAAAA==.Stx:BAAALgAECgYJDgAAAA==.',
Su='Subsdk:BAACLgAFFH8VAAIQAAYJpQ8KQwBvAQAQAAYJpQ8KQwBvAQAuAAQKfyYAAxAACAkeHs9AAAECABAACAkeHs9AAAECABkAAQnfH6owAFsAAAAA.Suih:BAAALgADCgUJBQAAAA==.Sunwalkers:BAAALgAECgUJBgAAAA==.Supfurry:BAAALgAFFAIJBAAAAA==.Sushhi:BAAALgAECgMJBgAAAA==.Suushy:BAAALgAECgYJEAAAAA==.',
Sw='Swam:BAAALgADCgkJCQABLgAFFAIJBwASAJsPAA==.Sweetl:BAAALgAECgQJBAAAAA==.',
Sy='Syreenaa:BAAALgAECgIJAwAAAA==.Systeni:BAAALgADCgkJCwAAAA==.',
['Sä']='Säek:BAAALgAECgMJCAAAAA==.',
['Sø']='Søøssø:BAAALgAECgYJCAAAAA==.',
Ta='Tacaagua:BAAALgAECgIJAwAAAA==.Taha:BAAALgAECgYJDgAAAA==.Taillys:BAAALgADCgMJBAAAAA==.Tainy:BAAALgAECgEJAQAAAA==.Takemywand:BAAALgADCgUJBQABLgAECgcJFAAWAFIQAA==.Takenaka:BAAALgADCgMJAwAAAA==.Tarez:BAAALgAFFAEJAQAAAA==.Tarfonir:BAAALgAECgYJCQAAAA==.Tashian:BAAALgADCgIJAgAAAA==.Tavalira:BAAALgADCgYJBgAAAA==.Taylör:BAAALgADCgEJAQAAAA==.',
Te='Tealen:BAAALgAECgEJAQAAAA==.Ted:BAAALgAECgcJDAAAAA==.Teiseken:BAAALgAECgcJBwAAAA==.Telaskei:BAAALgAECgUJBQAAAA==.Tempesfúria:BAAALgADCgIJAgAAAA==.Tenébria:BAAALgAECgcJBwAAAA==.Teratsemknk:BAAALgAECgUJBQAAAA==.',
Th='Thalyndrah:BAAALgADCgEJAQAAAA==.Tharnforge:BAAALgAECgEJAQAAAA==.Thejokker:BAACLgAFFH8IAAITAAMJ9AAWTABvAAATAAMJ9AAWTABvAAAuAAQKfxcAAhMABwl6BKVoALwAABMABwl6BKVoALwAAAAA.Themooster:BAABLgAFFH8PAAMIAAMJmA6EBQCEAAADAAIJYg2gkgCOAAAIAAMJHg6EBQCEAAAAAA==.Thepickles:BAAALgAECgUJDwAAAA==.Thepunk:BAAALgAECgQJEQAAAA==.Thesindorei:BAAALgAFFAEJAQAAAA==.Thintor:BAAALgADCgEJAQAAAA==.Thormento:BAABLgAECn8VAAIKAAcJkBGfWgBOAQAKAAcJkBGfWgBOAQAAAA==.Thraell:BAAALgAECgEJAQAAAA==.Threeß:BAAALgAECgQJBQAAAA==.',
Ti='Tigerblood:BAAALgADCgUJBQAAAA==.Tipooreeii:BAAALgADCgEJAQAAAA==.Titanicos:BAAALgAFFAIJAgAAAA==.',
Tj='Tjhunter:BAABLgAECn8fAAIBAAgJnQpeSQCNAQABAAgJnQpeSQCNAQAAAA==.',
To='Tobbiy:BAABLgAFFH8IAAIaAAMJWxifIgDXAAAaAAMJWxifIgDXAAAAAA==.Toddyb:BAAALgAECggJCwAAAA==.Tonytornado:BAAALgAECgEJAgAAAA==.',
Tr='Tranca:BAAALgADCgUJAwAAAA==.Tranh:BAAALgADCgkJFQAAAA==.Traxer:BAAALgADCgQJBAAAAA==.Tripäsecä:BAAALgAECgcJDgAAAA==.Troladora:BAABLgAECn8VAAIJAAYJqA75wwAEAQAJAAYJqA75wwAEAQAAAA==.Trévor:BAAALgAECgEJAQAAAA==.',
Ts='Tsreis:BAAALgADCgEJAQAAAA==.',
Tu='Tutydias:BAAALgAFFAIJAgAAAA==.',
Tw='Twoheavy:BAAALgADCgkJCQABLgAECgYJCQAEAAAAAA==.',
Ty='Tyrandrisa:BAAALgADCgIJAQAAAA==.',
['Tá']='Tátu:BAAALgADCgMJAwAAAA==.',
Uh='Uhdyr:BAAALgAECgQJBQAAAA==.',
Um='Ummetrodefio:BAAALgADCgEJAQAAAA==.',
Un='Unklevi:BAAALgADCgEJAQAAAA==.',
Ur='Urthemiel:BAAALgAECgEJAQABLgAECgYJBwAEAAAAAA==.',
Ut='Uthred:BAACLgAFFH8GAAMQAAMJnwGH1wCKAAAQAAMJnwGH1wCKAAAZAAIJUgAPKwA8AAAuAAQKfzEABBAACQkdB12aADUBABAACQnOBF2aADUBABkABgmqBG8MAOsAABoAAwmuCblKAGMAAAAA.',
Va='Vaelryn:BAAALgAECgYJCQABLgAECgYJBwAEAAAAAA==.Vagabundinho:BAAALgAECgQJBQAAAA==.Valdemmon:BAAALgAECgQJBwAAAA==.Valororo:BAABLgAECn8bAAIJAAkJtAYHjgBbAQAJAAkJtAYHjgBbAQAAAA==.Vandlesh:BAABLgAECn8WAAIJAAcJBw05pwAvAQAJAAcJBw05pwAvAQAAAA==.Vardha:BAAALgADCgQJBAAAAA==.Varka:BAAALgADCgYJGQAAAA==.',
Ve='Velkharun:BAAALgAECgQJDAABLgAFFAQJCwABALELAA==.Velkryon:BAAALgAECgUJBgAAAA==.Veltharyn:BAAALgAFFAEJAQAAAA==.Venatrin:BAAALgADCgkJCQAAAA==.Vess:BAAALgAECgQJBAAAAA==.Vexxv:BAABLgAECn8UAAIQAAUJshqnigBrAQAQAAUJshqnigBrAQAAAA==.Vexxz:BAAALgAECgYJCQAAAA==.',
Vi='Viquue:BAAALgADCgYJBgAAAA==.Viuvo:BAAALgADCgMJAwAAAA==.Vivisoft:BAAALgADCgMJAwAAAA==.',
Vl='Vlannytic:BAAALgAECgMJAwAAAA==.',
Vo='Voidrb:BAAALgADCgcJBwABLgAECggJGAANAAIcAA==.Vovogamer:BAAALgAECgQJBgAAAA==.',
Vu='Vunks:BAAALgAFFAEJAQAAAA==.',
['Vò']='Vòxs:BAACLgAFFH8SAAMNAAQJohSlIwDhAAANAAMJhxilIwDhAAATAAIJug/bQwCSAAAuAAQKf0sAAw0ACAk8JLYDAMQCAA0ABwnDJLYDAMQCABMABglHHoQuAPcBAAAA.',
Wa='Walkery:BAAALgADCgIJAgAAAA==.Wattari:BAABLgAECn8bAAIVAAYJDgTROwCEAAAVAAYJDgTROwCEAAAAAA==.Watters:BAAALgAECgUJCwABLgAFFAMJEgAkAHEPAA==.',
Wh='Whiteep:BAAALgADCgYJCAAAAA==.Whiteseraph:BAAALgADCgEJAQAAAA==.Whynchester:BAAALgADCgEJAQAAAA==.',
Wi='Wiilami:BAAALgADCgMJAwAAAA==.Windsailor:BAAALgAECgUJBQAAAA==.Wiserys:BAACLgAFFH8IAAIPAAMJvBJJhAC9AAAPAAMJvBJJhAC9AAAuAAQKfzMAAw8ACQmpIoYWAJ0CAA8ACQnmIYYWAJ0CABEABgn+HBwLAKwBAAAA.',
Wm='Wmarcão:BAABLgAECn8dAAMPAAcJrg8qCgD3AAAPAAcJ3A0qCgD3AAAOAAYJlA+YFgDwAAAAAA==.',
Wo='Wolfiez:BAAALgAECgUJDAAAAA==.Wolfnwar:BAAALgAECgQJEAAAAA==.Wopz:BAAALgADCgcJBwAAAA==.Worq:BAAALgADCgYJBgAAAA==.',
Wq='Wqz:BAACLgAFFH8GAAIBAAMJ7RtIKQDCAAABAAMJ7RtIKQDCAAAuAAQKfxcAAgEABwnHGZM2ANQBAAEABwnHGZM2ANQBAAAA.',
Wu='Wunamuno:BAAALgAECgEJAQAAAA==.',
Xa='Xallatath:BAAALgADCgUJBQAAAA==.Xamela:BAAALgADCgMJAwAAAA==.Xamãna:BAAALgAECgQJCQAAAA==.',
Xb='Xbleidexx:BAAALgADCgYJBgAAAA==.',
Xe='Xevron:BAAALgAECgQJBAAAAA==.Xexnetw:BAAALgAECgQJDQAAAA==.Xexnew:BAACLgAFFH8FAAIaAAIJLg6rNgBbAAAaAAIJLg6rNgBbAAAuAAQKfxkAAxoACQn0GuAPAA0CABoACQn0GuAPAA0CABAAAQlpB52QAScAAAAA.',
Xf='Xframengox:BAAALgADCgEJAQAAAA==.',
Xi='Xidevill:BAABLgAECn8jAAInAAYJ8QgWCQCbAAAnAAYJ8QgWCQCbAAAAAA==.Xinthorak:BAAALgADCgEJAgAAAA==.Xinzhou:BAAALgADCgQJCAAAAA==.Xiseth:BAAALgAECgIJAgAAAA==.Xixíca:BAAALgADCgUJBgAAAA==.',
Xl='Xladymaladax:BAAALgAECgQJBQAAAA==.',
Xm='Xmari:BAAALgAECgYJCAAAAA==.',
Xn='Xnyx:BAAALgAECgQJBAAAAA==.',
Xo='Xots:BAAALgAFFAEJAQAAAA==.',
Xs='Xseth:BAAALgAECgYJBwAAAA==.',
Xu='Xulaman:BAAALgAECgcJDgAAAA==.Xungodz:BAAALgADCgQJBAAAAA==.Xunxu:BAABLgAECn8ZAAMDAAYJdhMQhwBsAQADAAYJdhMQhwBsAQACAAEJJgM2ngArAAAAAA==.',
Xx='Xxcantsidex:BAAALgAECggJDQAAAA==.',
Xy='Xynrath:BAAALgADCgMJAwAAAA==.',
['Xÿ']='Xÿon:BAAALgAECgEJAQAAAA==.',
Ya='Yamëte:BAAALgAECgYJCgAAAA==.Yangyung:BAAALgAECgEJAQAAAA==.Yannadcg:BAACLgAFFH8GAAIdAAQJ9gJbIgCoAAAdAAQJ9gJbIgCoAAAuAAQKfy8AAh0ACQmRDCcqAHcBAB0ACQmRDCcqAHcBAAAA.',
Yo='Yorickundyer:BAAALgAECgUJCAAAAA==.Youdie:BAABLgAECn8YAAIjAAgJhRLwKgCEAQAjAAgJhRLwKgCEAQAAAA==.',
Yu='Yulthuan:BAAALgADCgMJAwAAAA==.',
Yv='Yvernus:BAAALgAECgQJBgAAAA==.',
Yz='Yziepala:BAAALgAECgMJBAAAAA==.',
Za='Zaaraki:BAABLgAECn9CAAMQAAkJ+htGAwAeAgAQAAkJfBtGAwAeAgAaAAgJ+hYKIgBCAQAAAA==.Zarolho:BAABLgAECn8VAAILAAYJSA6EUAAFAQALAAYJSA6EUAAFAQAAAA==.',
Ze='Zenitsua:BAAALgAECgYJCQAAAA==.Zenzeluk:BAAALgAECgMJAwAAAA==.Zephiir:BAABLgAECn8jAAIDAAYJIxgTEgDgAAADAAYJIxgTEgDgAAAAAA==.Zerdrax:BAAALgAECgEJAQAAAA==.Zeroxyz:BAAALgADCgYJBgABLgAECgYJGAAeAJUPAA==.Zeryen:BAAALgAECgEJAQAAAA==.',
Zf='Zfuntz:BAAALgAECgEJAgAAAA==.',
Zh='Zhunka:BAAALgADCgEJAwAAAA==.',
Zi='Ziikiipala:BAAALgAECgIJAwAAAA==.',
Zo='Zornak:BAAALgADCgUJBQAAAA==.',
Zz='Zzx:BAAALgADCgcJBwAAAA==.',
['Zé']='Zécasete:BAAALgADCgUJBwAAAA==.',
['Ál']='Álucard:BAABLgAECn8bAAIQAAkJHBCkCwATAQAQAAkJHBCkCwATAQAAAA==.',
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
