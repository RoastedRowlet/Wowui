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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Paladin-Retribution','Druid-Balance','Druid-Feral','Paladin-Protection','Mage-Frost','Unknown-Unknown','Shaman-Restoration','Shaman-Enhancement','Shaman-Elemental','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Fury','Hunter-Survival','Warrior-Protection','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Assassination','Priest-Holy','DemonHunter-Devourer','Monk-Windwalker','DemonHunter-Vengeance','Mage-Arcane','Hunter-Marksmanship','Priest-Discipline','Mage-Fire','Monk-Mistweaver','Priest-Shadow','DemonHunter-Havoc','Druid-Guardian','DeathKnight-Frost','Paladin-Holy','Monk-Brewmaster',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abortheira:BAAALgADCgUJBQAAAA==.',
Ac='Acelord:BAABLgAECn8eAAIBAAkJcRX1LwARAgABAAkJcRX1LwARAgAAAA==.Actaeon:BAAALgAECgQJBgAAAA==.',
Ad='Adaar:BAAALgAECgEJAQAAAA==.Adadebox:BAAALgAECgYJEAAAAA==.Adakat:BAAALgADCgEJAQAAAA==.Adanthedark:BAAALgADCgIJAgAAAA==.Adariom:BAAALgADCgUJCAAAAA==.Adrian:BAAALgADCgEJAQAAAA==.Adriannos:BAAALgAECgEJAQAAAA==.',
Ae='Aethir:BAAALgADCgYJBwAAAA==.',
Ag='Aghatta:BAAALgAECgYJBgAAAA==.Agonyy:BAAALgAECgUJEAAAAA==.Agrias:BAAALgAECgEJAgAAAA==.',
Ah='Aharadack:BAAALgAECgIJAgAAAA==.',
Ak='Akawaka:BAAALgAECgEJAQAAAA==.Akiji:BAAALgAECgEJAwAAAA==.Akimurad:BAAALgAECgYJBwAAAA==.',
Al='Alakazam:BAAALgADCgcJBwAAAA==.Alanie:BAAALgADCggJCAABLgAECggJIwACABUeAA==.Ald:BAAALgAECgEJAgAAAA==.Aldebaraum:BAAALgAECgcJDAAAAA==.Alexextreme:BAAALgAECgcJEQAAAA==.Aliaksandr:BAAALgAECgEJAQAAAA==.Alikth:BAAALgADCgYJBgAAAA==.Alista:BAAALgAECgMJAgAAAA==.Allandyr:BAACLgAFFH8LAAIBAAMJ0A5/VwDjAAABAAMJ0A5/VwDjAAAuAAQKf0cAAgEACQnZGA0gAFwCAAEACQnZGA0gAFwCAAAA.Alvarao:BAAALgAECgQJBAAAAA==.',
Am='Amandadark:BAAALgAECgEJAQAAAA==.Amano:BAAALgADCgYJDAAAAA==.',
An='Anaxthacia:BAAALgADCgMJAwAAAA==.Andarilho:BAAALgAECgYJBgAAAA==.Andinth:BAAALgAECgIJAgAAAA==.Andrepvp:BAAALgADCggJDwAAAA==.Andrit:BAAALgADCgEJAQAAAA==.Anellÿ:BAAALgAECgEJAQAAAA==.Angelloz:BAABLgAECn8rAAIDAAgJARINdAB7AQADAAgJARINdAB7AQAAAA==.Anjelvs:BAAALgAECgYJBgAAAA==.Anksunamoon:BAACLgAFFH8FAAICAAUJxAUGLQD5AAACAAUJxAUGLQD5AAAuAAQKfxkABAIACAmRD6A+AI8BAAIACAmRD6A+AI8BAAQABAnYEcFHAN4AAAUAAgk+EOs1AG0AAAAA.Annaoh:BAABLgAECn8cAAIDAAgJVB0oPQAFAgADAAgJVB0oPQAFAgAAAA==.Annia:BAAALgADCgYJBwAAAA==.Anyid:BAAALgAECgMJAwAAAA==.Anãodengoso:BAABLgAECn8pAAMDAAgJSCZgFQDpAgADAAgJSCZgFQDpAgAGAAIJIxKPOgBmAAABLgAECggJKQADAEgmAA==.',
Ap='Apökalÿpsïs:BAABLgAECn8eAAIHAAgJPxDBaQCiAQAHAAgJPxDBaQCiAQAAAA==.',
Ar='Arator:BAAALgAECggJDwAAAA==.Ardry:BAAALgADCgYJBgAAAA==.Argaloth:BAAALgAECgYJBwAAAA==.Argonzinha:BAAALgAECgEJAQAAAA==.',
As='Ashryel:BAAALgAECgEJAQAAAA==.Ashthon:BAABLgAECn8eAAIBAAcJgxxINgDVAQABAAcJgxxINgDVAQAAAA==.Asmitta:BAAALgADCgQJBAAAAA==.',
At='Atalantha:BAAALgAECgEJAQAAAA==.Atomicdk:BAAALgAECgUJBwAAAA==.Atomictank:BAAALgAECgcJEwAAAA==.Atonos:BAAALgAECgcJDAAAAA==.',
Au='Augustosg:BAAALgAECgYJDQABLgAECgYJEAAIAAAAAA==.Auquenai:BAAALgADCgUJBQAAAA==.Aurielis:BAAALgAECgEJAgAAAA==.',
Av='Averagemage:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAAALgAECgQJBAAAAA==.',
Az='Azadium:BAAALgAECgUJCgAAAA==.Azul:BAAALgAECgUJCgAAAA==.',
Ba='Badayaga:BAAALgADCgIJAgAAAA==.Bakunogrind:BAAALgAECgUJBQABLgAFFAQJBwAJAEMeAA==.Balragouldur:BAAALgAECgQJBgAAAA==.Balthar:BAACLgAFFH8FAAMJAAIJqAXzZQBgAAAJAAIJqAXzZQBgAAAKAAEJ5gJ1GAA8AAAuAAQKfyAABAsABwk6EptFAA0BAAsABwmjEZtFAA0BAAoABAkKEWsdAPUAAAkABAkGD9igAHUAAAAA.Barathrum:BAAALgADCgYJBgAAAA==.Barcaldas:BAAALgAECgUJBgAAAA==.Barrocø:BAAALgAECgQJBQABLgAECggJGAAMAAIcAA==.Basara:BAAALgAECgcJEgAAAA==.Batefraco:BAAALgADCgIJAgAAAA==.',
Bb='Bbiel:BAABLgAECn8kAAMNAAYJnRPFEgARAQANAAYJnRPFEgARAQAOAAEJtweWQAEuAAAAAA==.',
Be='Beatriz:BAAALgAECgYJCgAAAA==.Beelgarath:BAAALgAECgUJBwAAAA==.Beherit:BAAALgAECgMJBQAAAA==.Beliall:BAAALgADCgQJBQAAAA==.Belowlight:BAAALgAECgYJCgAAAA==.Belttazar:BAAALgADCgkJDwAAAA==.Bemmaith:BAAALgAECgQJBAAAAA==.Benzema:BAAALgADCgMJAgAAAA==.Berzan:BAAALgAECgUJCwAAAA==.Beyoond:BAACLgAFFH8bAAQOAAUJrxXQZwDjAAAOAAMJFBXQZwDjAAAPAAIJgBemHQBRAAANAAEJ+wcpJABIAAAuAAQKfzoABA4ACQm+HF0jAE0CAA4ACQm/G10jAE0CAA0ABAm3D+cxAPEAAA8AAwnBFgYdAMQAAAAA.',
Bh='Bhalin:BAAALgAECgUJCQABLgAECggJKAADAP4fAA==.',
Bi='Bielinski:BAAALgAECgQJBAAAAA==.Biinarc:BAAALgAECgEJAQAAAA==.',
Bl='Blackdut:BAACLgAFFH8GAAIOAAIJBgKEqgBsAAAOAAIJBgKEqgBsAAAuAAQKfxUAAw4ABwmyEdVoAGYBAA4ABwl5EdVoAGYBAA0ABAkpCogjAIgAAAAA.Blackfear:BAAALgAECgEJAQABLgAFFAIJBAAIAAAAAA==.Blackrøse:BAAALgADCgYJBgAAAA==.Blackteriaa:BAABLgAECn8UAAIHAAYJ/RP2lABJAQAHAAYJ/RP2lABJAQAAAA==.Blacrapumzel:BAAALgAECgMJAwAAAA==.Blakwolf:BAAALgAECgYJBwAAAA==.Blankis:BAAALgADCgYJCQAAAA==.Blastoize:BAAALgAECgIJAgAAAA==.Blizther:BAAALgADCgIJAgAAAA==.Bloodh:BAAALgAECgIJBgAAAA==.Bls:BAAALgADCgMJAwAAAA==.',
Bo='Boijf:BAAALgADCgEJAQAAAA==.Boladomal:BAAALgAECgMJBAAAAA==.Bones:BAAALgAECgEJAQAAAA==.Boromy:BAAALgAECgcJDAAAAA==.Boruck:BAAALgAECgIJAwAAAA==.',
Br='Braandom:BAAALgAECgcJEAAAAA==.Bradan:BAABLgAECn8eAAIQAAgJURWcKgAOAgAQAAgJURWcKgAOAgAAAA==.Brandomm:BAAALgAECgYJDwAAAA==.Branmir:BAAALgAECgMJBgAAAA==.Bridda:BAAALgAECgYJDAAAAA==.Brolho:BAAALgADCgEJAQAAAA==.Brusque:BAAALgAECgcJCgAAAA==.Bruzapaladin:BAAALgADCgUJBQAAAA==.',
Bt='Btrcaotics:BAAALgAECgIJCAAAAA==.Btrguard:BAAALgAECgIJAgAAAA==.',
['Bé']='Béto:BAABLgAECn8WAAIJAAkJXx32CgD8AgAJAAkJXx32CgD8AgAAAA==.',
['Bí']='Bíbs:BAABLgAECn8VAAIBAAgJkRMWUACmAQABAAgJkRMWUACmAQAAAA==.',
Ca='Cabanagé:BAAALgAECgUJBwAAAA==.Cabeludometa:BAAALgAECgYJCAAAAA==.Cabodecobre:BAAALgAECgUJCwAAAA==.Cainmarko:BAAALgAECgYJEAAAAA==.Caiowisk:BAABLgAECn8XAAMOAAgJBwcblQANAQAOAAgJOQUblQANAQANAAIJjxHROgA1AAAAAA==.Calir:BAAALgADCgYJFgAAAA==.Calçadora:BAACLgAFFH8GAAIRAAIJYxWTJQCTAAARAAIJYxWTJQCTAAAuAAQKf0EAAhEACQmqISgFANECABEACQmqISgFANECAAAA.Caquinha:BAAALgAECgEJAQAAAA==.Cardrok:BAAALgADCgEJAQAAAA==.Caridosa:BAAALgADCgUJBQAAAA==.Carnius:BAACLgAFFH8KAAMSAAMJmhUEGwCwAAASAAMJmhUEGwCwAAAMAAEJDAX9PwA0AAAuAAQKf0QABBIACAlHHi4QANoBABIACAkhHS4QANoBABAAAgm6IAyMAEoAAAwAAQkPHFtnAEMAAAAA.Casipala:BAAALgAECgIJAgAAAA==.Casuall:BAAALgAECgcJBwAAAA==.Cataclysm:BAAALgAECgMJBAAAAA==.Catalango:BAAALgAECgQJCgAAAA==.Catapó:BAAALgAECggJEwAAAA==.Catapózão:BAABLgAECn8zAAICAAkJniBBBgBMAwACAAkJniBBBgBMAwAAAA==.Catü:BAAALgAECgEJAQAAAA==.Cavernus:BAAALgADCgMJAwAAAA==.Caves:BAAALgADCgIJAgAAAA==.Caveston:BAAALgADCgUJCgAAAA==.',
Cb='Cbestabr:BAAALgADCgYJBgAAAA==.',
Ch='Chamadmordor:BAAALgAECgMJBQAAAA==.Charats:BAAALgADCgYJDQAAAA==.Charterine:BAAALgADCgYJBgAAAA==.Chaya:BAAALgADCgUJBQAAAA==.Chicknorris:BAAALgADCgUJBQAAAA==.Chifrudaxl:BAAALgAECgMJAwAAAA==.Chrisjks:BAAALgADCgYJCgAAAA==.',
Ci='Cindyn:BAAALgAECgEJAQAAAA==.',
Cl='Clared:BAAALgADCgEJAQAAAA==.Clarkcrente:BAAALgADCgYJBgABLgAECgMJAwAIAAAAAA==.Clebeya:BAAALgADCgQJBAAAAA==.Climps:BAABLgAECn8WAAIBAAgJRRc0OADyAQABAAgJRRc0OADyAQAAAA==.',
Co='Cobyx:BAAALgADCgcJDAAAAA==.Cocaferoz:BAAALgADCgEJAQAAAA==.Coffeeaddict:BAAALgADCgMJAwAAAA==.Colugo:BAAALgADCgIJAgAAAA==.Coriisco:BAAALgADCgIJAgAAAA==.Corollaxei:BAABLgAECn83AAQTAAkJsxdcCwAdAgATAAkJsxdcCwAdAgAUAAYJsQnbQwAPAQAVAAEJWAzbJAAyAAAAAA==.Cosculluela:BAAALgADCgUJBwAAAA==.Cosmuh:BAAALgAECgUJBQAAAA==.',
Cr='Creuzapriest:BAAALgAECgEJAQAAAA==.Crookedyoung:BAAALgAECgEJAwABLgAECgcJEAAIAAAAAA==.Cruzade:BAABLgAECn8VAAMGAAcJXxDyIQD4AAAGAAYJwBDyIQD4AAADAAYJdw8y4QDQAAABLgAFFAIJBAAIAAAAAA==.Cröwllëy:BAACLgAFFH8GAAIWAAMJiw2dmADSAAAWAAMJiw2dmADSAAAuAAQKfyMAAhYACAnZFwlBAPgBABYACAnZFwlBAPgBAAAA.',
Cu='Cubatao:BAABLgAECn8UAAIBAAYJUxQDfwAzAQABAAYJUxQDfwAzAQAAAA==.Cucaracha:BAABLgAECn8YAAIOAAYJVBaBbQBbAQAOAAYJVBaBbQBbAQAAAA==.',
Da='Dahhak:BAAALgAECgUJCwAAAA==.Dakhgagul:BAAALgADCgUJBQAAAA==.Dakshayani:BAAALgAECgQJBQAAAA==.Danielbrz:BAAALgAECgUJBwAAAA==.Daniellpvp:BAAALgADCgEJAQAAAA==.Danygatuxa:BAAALgAECgUJDQAAAA==.Daree:BAAALgAECgEJAQAAAA==.Darkenes:BAAALgAECgEJAQAAAA==.Darkinmt:BAAALgADCgcJCAAAAA==.Darknesstk:BAAALgAECgYJEAAAAA==.Darkowllskul:BAAALgAECgQJBwABLgAECgYJEgAIAAAAAA==.Darksiderptc:BAAALgADCgcJDwAAAA==.Darthmansur:BAAALgAFFAIJAwAAAA==.Dasmithy:BAAALgAECgEJAQAAAA==.',
De='Deadvi:BAABLgAECn8YAAIXAAgJXh02DQA7AgAXAAgJXh02DQA7AgAAAA==.Deadziin:BAABLgAECn8VAAIYAAcJowI4FwCwAAAYAAcJowI4FwCwAAAAAA==.Deathmäsk:BAAALgADCgcJBwAAAA==.Defensivepls:BAAALgAECgYJBQAAAA==.Demetrix:BAAALgADCgkJCgAAAA==.Dennyam:BAAALgAECgYJCQAAAA==.Derothey:BAABLgAECn8pAAIHAAgJYBZ+VQDWAQAHAAgJYBZ+VQDWAQAAAA==.Deservis:BAAALgADCgYJBgAAAA==.Deulorem:BAACLgAFFH8PAAIZAAQJih66DQBZAQAZAAQJih66DQBZAQAuAAQKfz0AAhkACQmBI8cBAI4DABkACQmBI8cBAI4DAAAA.Devilblade:BAABLgAECn8RAAIaAAgJXgmljwACAQAaAAgJXgmljwACAQAAAA==.',
Di='Diabolynn:BAAALgAECgcJEwAAAA==.',
Dk='Dkatraia:BAAALgAECgMJAwAAAA==.',
Dn='Dngfafinir:BAAALgAECgkJDAABLgAFFAUJDAADAFgXAA==.Dnghidan:BAACLgAFFH8MAAIDAAUJWBd1OwAlAQADAAUJWBd1OwAlAQAuAAQKfygAAgMACQmrHvohAKICAAMACQmrHvohAKICAAAA.Dngpain:BAAALgAECgUJCAABLgAFFAUJDAADAFgXAA==.Dngtobi:BAAALgAECgUJCQABLgAFFAUJDAADAFgXAA==.',
Do='Dollynhø:BAABLgAECn8eAAIbAAgJsxs5FAAOAgAbAAgJsxs5FAAOAgAAAA==.Donyed:BAAALgAECgQJCwAAAA==.Dottado:BAAALgADCgcJCgAAAA==.',
Dr='Drackah:BAAALgADCgcJBwAAAA==.Draconían:BAAALgAECgEJBwAAAA==.Dracón:BAAALgAECgUJCAAAAA==.Draigo:BAAALgAECgIJAgAAAA==.Dreykar:BAABLgAECn8uAAMaAAkJfBjoIQBAAgAaAAkJfBjoIQBAAgAcAAEJ2BxeKgBNAAAAAA==.Drogorn:BAAALgAECgUJCwAAAA==.Druidaezeki:BAAALgADCgYJCwAAAA==.Druidjm:BAAALgADCgMJAwAAAA==.Druvannar:BAAALgADCgEJAQAAAA==.Dröwränger:BAAALgADCgYJCwAAAA==.',
Du='Dultrasenegl:BAABLgAECn8hAAIBAAYJAA3yZQA2AQABAAYJAA3yZQA2AQAAAA==.Dunois:BAAALgAECgIJBgABLgAECgUJCgAIAAAAAA==.',
['Dä']='Dähäkä:BAABLgAECn8cAAIDAAgJsRwiMAA1AgADAAgJsRwiMAA1AgAAAA==.',
Ed='Edven:BAACLgAFFH8RAAITAAMJTAPvIQB/AAATAAMJTAPvIQB/AAAuAAQKfyEAAhMABgnKDMYlAEgBABMABgnKDMYlAEgBAAAA.',
Ei='Eini:BAAALgAECgEJAQAAAA==.',
El='Elbermt:BAAALgAECgEJAQAAAA==.Elbruxão:BAAALgAECgEJAQAAAA==.Eldrick:BAAALgADCgIJAgAAAA==.Eldros:BAAALgAECgYJCAAAAA==.Elementais:BAABLgAECn8ZAAIJAAcJQQ12UgBbAQAJAAcJQQ12UgBbAQAAAA==.Elgado:BAAALgAECgEJAwAAAA==.Elgatadexota:BAAALgADCgkJCgAAAA==.Eliksir:BAAALgAECgUJBQAAAA==.Ellanor:BAABLgAECn8dAAIHAAgJ+hgEUgDgAQAHAAgJ+hgEUgDgAQAAAA==.Elruth:BAAALgADCggJCAABLgAFFAQJDwAZAIoeAA==.Eltão:BAAALgAECgEJAQAAAA==.Elunah:BAAALgADCgQJBAAAAA==.Elwindor:BAAALgAECgEJAQAAAA==.Elyind:BAAALgADCgYJBwAAAA==.Elyn:BAAALgAECgQJBAAAAA==.',
Em='Emmymm:BAAALgAECgEJAQAAAA==.',
En='Endeavour:BAAALgADCgEJAQAAAA==.Enegadiel:BAABLgAECn8kAAIDAAcJWxUpbgCHAQADAAcJWxUpbgCHAQAAAA==.Enoia:BAAALgADCgcJDQAAAA==.',
Eq='Equidnah:BAAALgAECgIJAgAAAA==.',
Er='Erickya:BAAALgAECggJEgAAAA==.Ervadocè:BAABLgAECn8ZAAIEAAYJwhjOMgBAAQAEAAYJwhjOMgBAAQAAAA==.Ervelino:BAAALgAECgMJBAAAAA==.Eryz:BAAALgAECgMJAwAAAA==.',
Es='Estrogosbald:BAABLgAECn8ZAAIdAAgJMQxEBgBSAQAdAAgJMQxEBgBSAQAAAA==.',
Eu='Euteinvoco:BAAALgAECgIJAgAAAA==.',
Ev='Evely:BAABLgAECn8aAAIeAAcJgxjxDQByAQAeAAcJgxjxDQByAQAAAA==.',
Ex='Exarch:BAACLgAFFH8NAAIRAAQJaRTzEQAsAQARAAQJaRTzEQAsAQAuAAQKfysAAhEACQm/IRkDAAYDABEACQm/IRkDAAYDAAAA.',
Fa='Faengar:BAAALgAECgUJCAAAAA==.Falcondk:BAAALgAECgEJAQAAAA==.Falconess:BAAALgADCgEJAQAAAA==.',
Fe='Feathria:BAAALgAECgMJAwAAAA==.Felipebritoo:BAAALgAECgMJBgABLgAECgYJEgAIAAAAAA==.Fenrirsp:BAAALgAFFAIJBAAAAA==.Ferdruiid:BAAALgADCgkJEwAAAA==.Feropudo:BAAALgADCgkJDgAAAA==.Ferrarig:BAAALgAECgEJBQAAAA==.',
Fi='Figy:BAAALgAECgQJBAAAAA==.Filixy:BAAALgADCgYJBgAAAA==.',
Fl='Flemma:BAABLgAECn8YAAITAAgJJgcVHAAVAQATAAgJJgcVHAAVAQAAAA==.Flexer:BAAALgAECgIJAgAAAA==.Flores:BAAALgADCgMJBQAAAA==.Floridastyle:BAABLgAECn8fAAIfAAUJTxYMNQA1AQAfAAUJTxYMNQA1AQAAAA==.',
Fo='Foguerosa:BAACLgAFFH8JAAMHAAMJpRyQLwD4AAAHAAMJpRyQLwD4AAAgAAEJggDKBgAxAAAuAAQKfxYAAgcACAlpIVREAGsCAAcACAlpIVREAGsCAAAA.Folghunthir:BAAALgADCgQJBAAAAA==.',
Fr='Frankkquini:BAAALgADCgYJEgAAAA==.Friodokrl:BAACLgAFFH8IAAIWAAMJIw4RlgDVAAAWAAMJIw4RlgDVAAAuAAQKfzYAAxcACQkHHuENACECABcACQkuG+ENACECABYACAkdGo5BAPcBAAAA.Fritzgerhart:BAAALgAECgEJAQAAAA==.Frostkller:BAAALgADCgIJAgAAAA==.Frostmhaw:BAAALgADCgUJBQAAAA==.Frostreaper:BAAALgAECgQJBgAAAA==.',
Fu='Fubukiofhell:BAABLgAECn8aAAIHAAgJ1RkHPgAdAgAHAAgJ1RkHPgAdAgAAAA==.Fuginzao:BAAALgAECgEJAQAAAA==.Furtacor:BAAALgAECgEJAQAAAA==.Furyarh:BAAALgAECgMJAwAAAA==.',
['Fí']='Fí:BAAALgADCggJDgABLgAECgkJHQABALAaAA==.',
Ga='Gabana:BAAALgADCgQJBAAAAA==.Gabdobbuh:BAAALgAECgUJCAAAAA==.Gabn:BAAALgAECgMJBgAAAA==.Gafgar:BAAALgADCgUJCQAAAA==.Gaila:BAAALgAECgIJBgAAAA==.Galduin:BAACLgAFFH8FAAIQAAMJzAgzNgDCAAAQAAMJzAgzNgDCAAAuAAQKfy8AAhAACQlBGA8XAC8CABAACQlBGA8XAC8CAAAA.',
Ge='Gedexx:BAAALgAECgMJAgAAAA==.Geduntruppa:BAAALgAECgYJBgAAAA==.Gentioiroh:BAAALgAECgQJBAAAAA==.',
Gh='Ghorderp:BAAALgADCgcJDAAAAA==.Ghosstt:BAAALgAECgEJAgAAAA==.Ghoulrozon:BAAALgADCgYJBgAAAA==.',
Gi='Giovannapala:BAABLgAECn8ZAAIDAAgJ/A2nlgA7AQADAAgJ/A2nlgA7AQAAAA==.Giovannasham:BAAALgAECgEJAwAAAA==.Giripoca:BAAALgAECgQJCQAAAA==.',
Gl='Gladsmonge:BAABLgAECn8pAAIhAAcJ3h8jFABpAgAhAAcJ3h8jFABpAgAAAA==.Glorcckk:BAAALgAECgMJAwAAAA==.',
Gn='Gnomagga:BAAALgAECgcJEAABLgAECggJNgAGAB8cAA==.Gnomohabe:BAAALgADCgQJBgAAAA==.',
Go='Goddofwarr:BAAALgADCggJEQAAAA==.Gonb:BAAALgADCgUJBQAAAA==.Goueki:BAABLgAECn80AAMBAAgJmBrCLAAeAgABAAgJmBrCLAAeAgAeAAIJSwEtgwA8AAAAAA==.',
Gr='Greenzle:BAAALgAECgUJBgAAAA==.Grillnborst:BAAALgADCgEJAgAAAA==.Grilonp:BAAALgADCgQJCAAAAA==.Grogath:BAAALgAECgQJCAAAAA==.Grogtixa:BAAALgAECggJCQABLgAECgkJKgALAFcWAA==.Gromoff:BAABLgAFFH8HAAIOAAIJwiSQeQDCAAAOAAIJwiSQeQDCAAAAAA==.Grunmonk:BAAALgADCgEJAQAAAA==.Grømmar:BAAALgADCgMJAwAAAA==.',
Gu='Gudangara:BAAALgADCgYJBgAAAA==.Gumy:BAAALgAECgEJBAAAAA==.Guztaverdead:BAAALgADCgQJBAAAAA==.',
['Gü']='Güistrong:BAAALgADCgIJAwAAAA==.',
Ha='Haakaí:BAAALgAECgUJEAAAAA==.Haandir:BAAALgAECgIJBAAAAA==.Hackterin:BAAALgADCgYJBgAAAA==.Hadorah:BAAALgAECgUJBgAAAA==.Haerys:BAAALgAFFAEJAQAAAA==.Handhemirr:BAAALgAECgMJBAAAAA==.Harany:BAABLgAECn8mAAMfAAgJDBf5EQBJAgAfAAgJDBf5EQBJAgAiAAYJywuwRQDvAAAAAA==.Harrypotinho:BAABLgAECn8wAAIOAAgJYxpZMAARAgAOAAgJYxpZMAARAgAAAA==.Haunexd:BAAALgADCgMJAwAAAA==.Havenna:BAAALgAECgUJCAAAAA==.',
He='Headøhunter:BAAALgAECgEJAgAAAA==.Healgate:BAAALgAECgEJAQAAAA==.Heeythaly:BAAALgADCgcJDwAAAA==.Helessa:BAAALgAECgEJAQAAAA==.Hellenah:BAAALgADCggJCAAAAA==.Herablack:BAAALgAECgMJAwAAAA==.Herika:BAAALgADCgMJAwAAAA==.',
Hi='Hidenz:BAAALgADCgIJAwAAAA==.',
Ho='Hoem:BAAALgAECgMJAwAAAA==.Holand:BAAALgAECgYJDAAAAA==.Holydread:BAAALgAECgIJAgAAAA==.',
Hu='Hulig:BAABLgAECn8oAAMDAAgJ/h9DJABqAgADAAgJ/h9DJABqAgAGAAEJAQdxUAAnAAAAAA==.Hunthearthas:BAAALgAECgMJAwAAAA==.',
['Hø']='Høkulani:BAABLgAECn8cAAIHAAcJchHTgwBpAQAHAAcJchHTgwBpAQAAAA==.',
Ib='Ibrad:BAAALgAECgQJBAAAAA==.Ibuprofens:BAAALgAECgEJAQAAAA==.',
Ic='Iceyag:BAAALgAECgIJAgAAAA==.',
Ik='Ikiam:BAAALgAECgUJCQAAAA==.Ikslawok:BAAALgADCgYJEAAAAA==.',
Il='Ileria:BAAALgAECgYJBwAAAA==.Iliriana:BAAALgAECgEJAQAAAA==.Illarion:BAAALgADCgQJBAAAAA==.Illidanos:BAABLgAECn8cAAIjAAgJ/RG9HQB8AQAjAAgJ/RG9HQB8AQAAAA==.Illidansan:BAAALgAECgQJBQABLgAECgYJCwAIAAAAAA==.Illidris:BAAALgAECgUJBQAAAA==.Illumiinated:BAABLgAECn8UAAIkAAYJiwxlHADCAAAkAAYJiwxlHADCAAAAAA==.',
In='Incarus:BAAALgAECgcJCgAAAA==.Incognita:BAAALgAECgEJAQAAAA==.Indis:BAAALgADCgQJBgAAAA==.Interst:BAAALgAECgEJAQAAAA==.',
Ir='Irion:BAAALgAECgQJBQAAAA==.',
Is='Iscalio:BAAALgAECgYJCgAAAA==.',
It='Itatchii:BAAALgAECgQJBQAAAA==.',
Iv='Ivinhosilva:BAAALgADCgYJBgAAAA==.',
Ja='Jackdawnsong:BAABLgAECn8UAAIHAAgJuBeqSAD7AQAHAAgJuBeqSAD7AQAAAA==.Jaene:BAAALgADCgYJCQAAAA==.Jahuun:BAABLgAECn8ZAAIDAAcJ4wsBowAnAQADAAcJ4wsBowAnAQAAAA==.Jamantoso:BAAALgAECgEJAQAAAA==.',
Je='Jeess:BAAALgADCgMJAwAAAA==.Jefflich:BAABLgAECn8iAAMWAAgJ4AqUiQBuAQAWAAgJiwmUiQBuAQAlAAEJhxJINwAuAAAAAA==.',
Jg='Jg:BAAALgAECgUJBwABLgAECgYJDgAIAAAAAA==.',
Ji='Jinknu:BAAALgAECgIJBAAAAA==.',
Jo='Jottapeg:BAAALgADCgcJAwAAAA==.',
Ju='Jubard:BAAALgADCgkJDAAAAA==.Juliamarques:BAAALgAECgMJBAAAAA==.',
['Jü']='Jüllÿe:BAAALgADCgEJAQAAAA==.',
Ka='Kaaellthas:BAAALgAECgQJDQAAAA==.Kacolux:BAAALgADCgEJAQAAAA==.Kaisaargente:BAAALgAECgEJAQAAAA==.Kakarotho:BAAALgAECgMJCQAAAA==.Kalarath:BAAALgAECgYJBgAAAA==.Kaldonios:BAAALgADCgcJEgAAAA==.Kalma:BAAALgAECgEJAQAAAA==.Kamasutram:BAAALgADCgYJCwAAAA==.Kanadriel:BAAALgAECgcJDAAAAA==.Kanarinho:BAABLgAECn80AAICAAkJIh9gCAAqAwACAAkJIh9gCAAqAwAAAA==.Karmussie:BAAALgADCgEJAQAAAA==.Karmysh:BAAALgAECgMJAwAAAA==.Katari:BAAALgAECgYJCgABLgAECgkJIAAmAAMfAA==.Kayanz:BAAALgADCgUJBQAAAA==.Kazandra:BAAALgADCgYJBgAAAA==.',
Ke='Kendars:BAABLgAECn8VAAQEAAYJ0xKfSAAKAQAEAAUJJhKfSAAKAQACAAUJFQ+5dgDzAAAFAAEJhRUxRABDAAABLgAFFAMJBwAXALAMAA==.Ket:BAAALgADCgMJAwAAAA==.',
Kh='Khanmir:BAAALgAECgMJBgAAAA==.Kharon:BAAALgAECgYJBwAAAA==.Khild:BAAALgAECgYJDQAAAA==.Khonar:BAAALgADCgUJBwAAAA==.',
Ki='Killerdek:BAAALgAECgUJBQAAAA==.Killshoty:BAAALgAECgEJAgAAAA==.',
Kl='Klissera:BAAALgADCgQJBAAAAA==.Kluzlocak:BAABLgAECn8iAAIfAAYJUQwIOgAaAQAfAAYJUQwIOgAaAQAAAA==.',
Kn='Knnabys:BAAALgAECgEJAQAAAA==.',
Ko='Komah:BAAALgAECgEJAQAAAA==.Korav:BAAALgAECgMJCQAAAA==.Korium:BAAALgADCgUJBQABLgAECgkJNwASAB4kAA==.Koruno:BAAALgADCgYJBgAAAA==.',
Kr='Krosn:BAAALgAECgEJAQAAAA==.Krozhul:BAAALgAECgcJDQAAAA==.Krypthor:BAAALgAECgEJAQAAAA==.',
Ku='Kurnous:BAAALgAECgEJAQAAAA==.Kutirenzo:BAAALgADCgUJBwAAAA==.',
La='Lafiel:BAAALgAECgcJEQAAAA==.Lagertha:BAAALgADCgYJBgAAAA==.Lahnara:BAAALgAECgcJCAAAAA==.Lambayoda:BAAALgAECgYJBwAAAA==.Lamelo:BAAALgADCgYJBgAAAA==.Lanmo:BAAALgAFFAEJAQAAAA==.Largatixazul:BAAALgADCgUJBgAAAA==.Lataria:BAAALgADCgEJAQAAAA==.Laurea:BAAALgAECgkJEQABLgAECgkJIAAmAAMfAA==.',
Le='Leebron:BAAALgAECgYJDAAAAA==.Lefthalas:BAAALgAECgUJCgAAAA==.Leitchero:BAAALgAECgIJAgAAAA==.Lemaz:BAAALgAECgEJAQAAAA==.Lemonhunter:BAAALgAECgYJCAAAAA==.Leonelmessi:BAAALgAFFAQJAgAAAA==.Lesco:BAAALgADCgMJAwAAAA==.',
Li='Lianele:BAAALgAECgcJDAAAAA==.Liaras:BAABLgAECn8pAAMZAAgJXBe2HADTAQAZAAgJXBe2HADTAQAiAAIJzABFaQAmAAAAAA==.Libertinagem:BAAALgAECgYJDQAAAA==.Lichtbaum:BAABLgAECn8hAAMCAAgJyxxaIABAAgACAAgJyxxaIABAAgAEAAUJwxlhOQAfAQAAAA==.Lightsertrop:BAAALgADCgIJAgAAAA==.Liifecomm:BAACLgAFFH8TAAIZAAUJSRS7DABnAQAZAAUJSRS7DABnAQAuAAQKfzwAAhkACQl+HmQLAKQCABkACQl+HmQLAKQCAAAA.Liike:BAAALgAECgcJDAAAAA==.Linestra:BAAALgADCgUJBQAAAA==.Liniak:BAAALgAECgcJEAAAAA==.Lisong:BAAALgADCgUJCQAAAA==.Littlepurple:BAACLgAFFH8JAAIaAAMJzxJ7GwD2AAAaAAMJzxJ7GwD2AAAuAAQKfyQAAhoACQl0HJwYAMICABoACQl0HJwYAMICAAAA.',
Lo='Longhai:BAAALgADCgUJCAAAAA==.Lookatmylock:BAABLgAECn8iAAMNAAYJ/xudCwB3AQANAAYJ/xudCwB3AQAOAAIJmBGSEQFLAAAAAA==.Lordpain:BAAALgAECgcJDQAAAA==.Lortherti:BAAALgAECgIJAgAAAA==.Lorwin:BAABLgAECn8UAAIBAAgJhBmVQwDLAQABAAgJhBmVQwDLAQAAAA==.Lotusbr:BAAALgADCgEJAQAAAA==.Louisenacioo:BAABLgAECn8UAAMTAAcJUhB/FAB6AQATAAcJUhB/FAB6AQAUAAMJqwWidABsAAAAAA==.Loátrak:BAAALgADCgMJAwAAAA==.',
Lu='Luanne:BAAALgADCgEJAQAAAA==.Luccablack:BAAALgAECgMJAwAAAA==.Luccagelido:BAAALgAECgMJBAAAAA==.Lucyx:BAAALgAECgIJAgAAAA==.Luidar:BAAALgAECgQJBAAAAA==.Lukaslions:BAABLgAECn8gAAIQAAkJaA+cKQCrAQAQAAkJaA+cKQCrAQAAAA==.Lunarie:BAAALgAECgYJEwABLgAECgcJBwAIAAAAAA==.Luphoe:BAABLgAECn8nAAMCAAcJ9RzHJwAWAgACAAcJ9RzHJwAWAgAEAAQJkw7ZXgCMAAAAAA==.Luxanä:BAAALgAECgYJBgAAAA==.',
['Lé']='Léio:BAAALgADCgcJCAAAAA==.Léora:BAAALgADCgIJAgAAAA==.',
['Lø']='Lørdsith:BAAALgAECgYJCAABLgAECggJBgAIAAAAAA==.',
['Lÿ']='Lÿcäns:BAAALgADCgMJAwAAAA==.',
Ma='Madagalux:BAABLgAECn8rAAIPAAgJQQp2DgBhAQAPAAgJQQp2DgBhAQAAAA==.Madalenna:BAAALgAECgMJBQAAAA==.Madjack:BAAALgAECgMJAwAAAA==.Madushi:BAAALgAFFAEJAQAAAA==.Madzerø:BAAALgAECgEJAgAAAA==.Magatiun:BAAALgADCgMJBAAAAA==.Magogunt:BAABLgAECn8kAAIHAAkJMxFwUADkAQAHAAkJMxFwUADkAQAAAA==.Maguul:BAABLgAECn8ZAAIGAAgJ5hWREACtAQAGAAgJ5hWREACtAQAAAA==.Magzifeh:BAABLgAECn8UAAIBAAcJ3SDTNgD3AQABAAcJ3SDTNgD3AQAAAA==.Mahadevi:BAAALgADCgIJAgAAAA==.Mahdemon:BAAALgAECgYJCQAAAA==.Maiconhood:BAAALgAFFAEJAQAAAA==.Malandrvs:BAAALgAFFAEJAwAAAA==.Maljamim:BAAALgADCgIJAgAAAA==.Mamuthwar:BAABLgAECn8ZAAMQAAcJnRgeNgDQAQAQAAcJnRgeNgDQAQAMAAEJMQ7ZQQA1AAAAAA==.Mandingavudu:BAAALgAECgYJBwABLgAECggJGgAkADAdAA==.Manei:BAAALgAECgMJAwAAAA==.Mangalarga:BAAALgADCgEJAQAAAA==.Manmoden:BAAALgADCgUJBQABLgAECggJGgAkADAdAA==.Mannatur:BAABLgAECn8aAAMkAAgJMB1nEADRAQAEAAcJAxylGQDyAQAkAAgJahdnEADRAQAAAA==.Manopaladino:BAAALgADCgYJBgAAAA==.Manowlo:BAAALgAECgMJAwAAAA==.Manzagon:BAAALgAECgYJCQABLgAECggJGgAkADAdAA==.Marandracon:BAAALgADCgMJAwAAAA==.Marmelo:BAAALgADCgQJBAAAAA==.Marretasanta:BAABLgAECn8kAAIDAAcJCRTphgBXAQADAAcJCRTphgBXAQAAAA==.Maruterrestr:BAAALgAECgMJAgAAAA==.Marù:BAAALgAECgYJCwAAAA==.Marúh:BAACLgAFFH8SAAIJAAUJPRhMHQBoAQAJAAUJPRhMHQBoAQAuAAQKfycAAgkACAnzIsQFABYDAAkACAnzIsQFABYDAAAA.Matedellmor:BAAALgADCgIJAwAAAA==.Matroná:BAAALgADCggJBwAAAA==.Maxmorf:BAAALgADCgUJBQAAAA==.Mayarabr:BAAALgAECgYJDQAAAA==.Mazeratos:BAAALgAECgMJBQAAAA==.',
Mc='Mcorelhao:BAAALgADCgEJAQAAAA==.',
Me='Medoza:BAAALgAECgQJBgAAAA==.Megrezz:BAAALgAECgEJAQAAAA==.Mehiel:BAAALgAECgEJAQAAAA==.Mekihlvshtak:BAAALgAECgYJBwAAAA==.Meliøðas:BAAALgADCgEJAQAAAA==.Mendingu:BAABLgAECn8YAAMMAAgJAhxUGQCFAQAQAAgJRxgYKAAdAgAMAAQJ/CBUGQCFAQAAAA==.Mercenarybr:BAAALgAECgEJAgAAAA==.Merumim:BAAALgAECgYJCwAAAA==.Metalgirl:BAAALgADCgYJCwAAAA==.Methamorfo:BAAALgADCggJCQAAAA==.',
Mi='Midrão:BAAALgAECggJEwAAAA==.Miisuky:BAAALgADCgUJBAAAAA==.Mikasaackerr:BAAALgAECgEJAgAAAA==.Milczarek:BAAALgAECgEJAwAAAA==.Mindlocker:BAABLgAECn8dAAIOAAcJMwlZjQAbAQAOAAcJMwlZjQAbAQAAAA==.Minorus:BAAALgAECgcJEgAAAA==.Mistifs:BAABLgAECn8kAAIhAAgJ3x1xDgCnAgAhAAgJ3x1xDgCnAgAAAA==.Miticamais:BAAALgADCgMJAwAAAA==.',
Mo='Modogz:BAAALgADCgYJBgAAAA==.Momongadk:BAAALgADCgcJBwAAAA==.Monkeydking:BAAALgADCgUJBQAAAA==.Morania:BAABLgAECn8XAAINAAgJUwYRFgDoAAANAAgJUwYRFgDoAAAAAA==.Mordekais:BAAALgAECgIJAgAAAA==.Morganne:BAAALgAECgEJAQAAAA==.Morinami:BAAALgAECgQJBAAAAA==.Moriyama:BAABLgAECn8nAAMCAAgJshw6KQAAAgACAAcJuBs6KQAAAgAEAAIJExK9ZgByAAAAAA==.Morphisz:BAAALgAECggJDQABLgAECggJGgAkADAdAA==.Morphiszs:BAAALgAECgMJBQABLgAECggJGgAkADAdAA==.Morphizs:BAAALgAECgEJAwABLgAECggJGgAkADAdAA==.Mortesan:BAAALgAECgEJAQABLgAECgYJCwAIAAAAAA==.',
Mp='Mpastor:BAAALgADCgUJBQAAAA==.',
Mu='Muca:BAAALgADCgEJAQAAAA==.Muho:BAAALgADCgEJAQAAAA==.Mukonha:BAABLgAECn8jAAIOAAcJeA4nhQAqAQAOAAcJeA4nhQAqAQAAAA==.',
['Mã']='Mãoleves:BAAALgADCgEJAQAAAA==.',
['Må']='Måximus:BAAALgAECgUJCAAAAA==.',
['Mü']='Müller:BAAALgADCgEJAQABLgAECgcJEAAIAAAAAA==.',
Na='Naeryndam:BAAALgADCgEJAQAAAA==.Namyara:BAAALgAECgEJAQAAAA==.Narutowow:BAAALgADCgMJAwAAAA==.Natcmd:BAAALgADCggJFwAAAA==.Nathilell:BAAALgADCgIJAgAAAA==.Navira:BAAALgAECgEJAQAAAA==.Nayanna:BAAALgADCgcJDQAAAA==.Nazzd:BAAALgAECgEJAQABLgAECgQJBQAIAAAAAA==.',
Ne='Negblack:BAAALgAFFAMJBAAAAA==.Neggi:BAAALgAECgUJBwAAAA==.Nemesysy:BAAALgAECgMJAwAAAA==.Nerphien:BAAALgADCgUJBQAAAA==.Nesktpally:BAAALgAECgcJCAAAAA==.Netbrood:BAAALgADCgUJBgABLgAECgUJBwAIAAAAAA==.Netbrother:BAAALgAECgUJBwAAAA==.Nethdorai:BAAALgADCgQJBAAAAA==.Netherbane:BAABLgAECn8mAAMMAAcJmhoQEQDXAQAMAAcJmhoQEQDXAQAQAAIJGQ8xmgA0AAAAAA==.Nezuko:BAAALgAECgUJBQABLgAECggJMAAOAGMaAA==.',
Ni='Nightmære:BAAALgAECgQJCwAAAA==.Nikelok:BAABLgAECn8XAAIOAAcJjQbVoAD5AAAOAAcJjQbVoAD5AAAAAA==.Ninfador:BAABLgAECn8eAAIfAAYJgxe5LgBYAQAfAAYJgxe5LgBYAQAAAA==.Ninpus:BAAALgAECgMJAwAAAA==.',
No='Noobmasteer:BAAALgADCgIJAgAAAA==.Nooneknow:BAACLgAFFH8HAAIWAAQJTBV/hADsAAAWAAQJTBV/hADsAAAuAAQKfzkAAhYACQlUISkUAMcCABYACQlUISkUAMcCAAAA.Nosios:BAAALgAECgYJBgAAAA==.Nosrede:BAAALgAECgEJAQAAAA==.Notz:BAAALgADCgMJBAAAAA==.',
Nu='Nucciwarrior:BAAALgAECgUJCAAAAA==.Nuccixama:BAAALgAECgcJCQAAAA==.',
Ny='Nyde:BAAALgAECgMJAwAAAA==.',
['Nø']='Nøar:BAAALgADCgIJAgAAAA==.',
Oa='Oakshlar:BAAALgAFFAEJAQAAAA==.',
Oc='Ocelaris:BAAALgAECgEJAgAAAA==.',
Oh='Ohlu:BAAALgAECgYJCQAAAA==.Ohluh:BAAALgAECgcJDQAAAA==.',
Or='Oryana:BAAALgAECgEJAQAAAA==.Oríon:BAAALgADCgIJAgAAAA==.',
Ot='Otton:BAABLgAECn8mAAIDAAgJhwgMsgAQAQADAAgJhwgMsgAQAQAAAA==.',
Ov='Overnigth:BAAALgADCgIJAgAAAA==.Overwalker:BAAALgAECgEJAgAAAA==.Ovosemdente:BAAALgADCgEJAQAAAA==.',
Ow='Owllskull:BAAALgAECgYJEgAAAA==.',
Oz='Ozovo:BAAALgAECgcJDwAAAA==.',
Pa='Pacoka:BAAALgADCgQJBQAAAA==.Padrafferty:BAAALgADCgcJBwAAAA==.Paidesanto:BAABLgAECn8WAAQPAAcJyhDVGADmAAAPAAYJKg/VGADmAAAOAAYJMgsVyQC3AAANAAMJ5RGTRgCcAAAAAA==.Paidesantox:BAABLgAECn8YAAIEAAcJRAldQQD5AAAEAAcJRAldQQD5AAABLgAFFAMJBQAQAMwIAA==.Paidocharles:BAAALgAECgEJAgAAAA==.Paladinokun:BAAALgAECgYJCwAAAA==.Palanis:BAAALgAECgcJBwAAAA==.Palazarta:BAABLgAECn8XAAIDAAcJBAoCswAPAQADAAcJBAoCswAPAQAAAA==.Pandavoli:BAAALgAECgUJDAAAAA==.Pangolinho:BAAALgAECgQJBQAAAA==.Panky:BAAALgAECgQJBAAAAA==.Panquecudo:BAAALgADCgIJAgAAAA==.',
Pd='Pdois:BAAALgADCgMJAwAAAA==.',
Pe='Pesscador:BAAALgAECgMJAwAAAA==.Petrolesk:BAAALgAECgYJEQAAAA==.',
Pi='Piriguetee:BAAALgADCgEJAQAAAA==.Pirro:BAAALgAECgEJAQAAAA==.Pisadinha:BAAALgADCgcJBwAAAA==.',
Pk='Pkzimn:BAAALgADCgUJBQAAAA==.',
Pl='Playsson:BAAALgAECgYJEgAAAA==.Plottwist:BAAALgADCgcJDwABLgAECgkJNwAWAOkZAA==.',
Po='Pogonus:BAAALgADCgIJAgAAAA==.Pontocego:BAAALgAECgQJBAAAAA==.Pororocaa:BAAALgAECgQJBwAAAA==.Posturado:BAAALgADCgEJAQAAAA==.Powerworth:BAAALgAECgEJAQAAAA==.',
Pr='Pravios:BAAALgAECggJDgAAAA==.Priestkill:BAAALgADCgcJCQAAAA==.Prikithon:BAAALgAECgEJAQAAAA==.Primewolf:BAAALgAECgMJAwAAAA==.',
Ps='Psicomanic:BAAALgADCgMJAwAAAA==.',
Pt='Pterodactilo:BAAALgAECgYJAQAAAA==.',
Pu='Puherito:BAAALgAECgUJCwAAAA==.Purgas:BAAALgAFFAEJAQAAAA==.',
Qu='Quinthalam:BAAALgADCgMJAwAAAA==.',
Ra='Rafac:BAAALgAECgEJAgABLgAFFAEJAQAIAAAAAA==.Rafazinho:BAAALgADCgQJBAAAAA==.Ramyna:BAAALgAECgMJBQAAAA==.Ramyra:BAAALgADCgcJDQAAAA==.Raphaeldh:BAAALgAECgEJAgAAAA==.Raphahunterr:BAAALgADCgEJAQAAAA==.Raposa:BAAALgADCgEJAQAAAA==.Raposinha:BAAALgADCgMJAwAAAA==.Rarkway:BAAALgAECgcJCwAAAA==.Ravenblak:BAAALgADCgMJAwAAAA==.Rayanne:BAAALgADCgYJBgAAAA==.',
Re='Reckfull:BAAALgAECgYJBgAAAA==.Regininha:BAAALgAECgEJAQAAAA==.Reloumifrend:BAAALgAECgcJCgAAAA==.Rendros:BAAALgADCgUJBQAAAA==.',
Rh='Rhaegaar:BAAALgAECgcJDQAAAA==.Rhanideri:BAAALgADCgEJAQAAAA==.Rhodinius:BAAALgAECgMJCAAAAA==.',
Ri='Rivotreel:BAAALgADCgQJBAAAAA==.',
Ro='Robeerth:BAAALgAFFAIJBAAAAA==.Rochera:BAAALgAECgEJAQAAAA==.Rokhanar:BAAALgAECgUJCwAAAA==.',
Ru='Rudemonster:BAAALgAECgEJAQAAAA==.Ruhtarr:BAAALgADCgEJAQAAAA==.',
Ry='Ryukato:BAAALgAECgQJBQAAAA==.',
Sa='Saek:BAAALgAECgcJEgAAAA==.Saelor:BAAALgAECgEJAgAAAA==.Sanderclone:BAAALgAECgEJAQAAAA==.Sanguenafaca:BAAALgADCgYJCgAAAA==.Santiss:BAABLgAECn8WAAIDAAYJDhUboQAqAQADAAYJDhUboQAqAQAAAA==.Santorini:BAAALgAECgcJDQAAAA==.Saphirot:BAAALgADCgUJBQAAAA==.Saphis:BAAALgADCgEJAQAAAA==.Sardado:BAAALgAECgEJAQAAAA==.Sardron:BAAALgADCgMJAwAAAA==.',
Sc='Scanorr:BAAALgAECgYJDAAAAA==.Scheffers:BAABLgAECn8VAAIiAAYJvxKgNgAzAQAiAAYJvxKgNgAzAQAAAA==.',
Se='Selah:BAAALgADCgMJBQAAAA==.Selver:BAAALgAECgcJCAABLgAFFAcJGgAiALAaAA==.Selüne:BAAALgAECgcJDQAAAA==.Sephora:BAAALgAECgYJCwABLgAECggJKQAZAFwXAA==.Sevagoth:BAAALgAECggJDQAAAA==.',
Sh='Shadowlock:BAAALgADCgIJAQABLgAECgYJDwAIAAAAAA==.Shadowmornac:BAAALgAECgMJBgAAAA==.Shamanica:BAAALgAECgEJAgAAAA==.Shamateus:BAAALgADCggJEwAAAA==.Shasuna:BAAALgADCgIJAgAAAA==.Shaunnun:BAAALgADCgEJAQAAAA==.Shenloong:BAAALgADCgYJBgAAAA==.Shinnók:BAAALgAECgIJAgAAAA==.Shiíro:BAAALgAFFAIJBAABLgAFFAUJEwADABAkAA==.Shynato:BAAALgADCgEJAQAAAA==.Shynock:BAAALgADCgEJAQAAAA==.Shyriull:BAAALgAECgEJAQAAAA==.Shyzuno:BAAALgADCgQJBAAAAA==.Shãka:BAAALgADCgMJAwAAAA==.',
Si='Siladriel:BAAALgADCgMJAwAAAA==.Sirgonzo:BAABLgAECn8XAAIDAAkJtxdsOgAOAgADAAkJtxdsOgAOAgAAAA==.',
Sk='Skullexus:BAAALgAECgMJBAAAAA==.Skunkbr:BAAALgADCgEJAQAAAA==.',
Sl='Sleepychety:BAAALgAECgUJBgAAAA==.Slowsmoke:BAAALgADCgYJBwAAAA==.Slyfer:BAABLgAFFH8FAAIBAAIJwRSIcACdAAABAAIJwRSIcACdAAAAAA==.',
Sn='Snatzz:BAAALgADCgMJAgAAAA==.',
So='Soggoth:BAAALgADCgkJCQAAAA==.Solk:BAAALgAECgMJBgAAAA==.Sontarfury:BAAALgAECgEJAQAAAA==.Sorim:BAABLgAECn8mAAICAAgJeBs7GwBiAgACAAgJeBs7GwBiAgAAAA==.Soryan:BAABLgAECn8pAAMCAAgJuBNwNADAAQACAAgJuBNwNADAAQAEAAUJ+g3xTADKAAAAAA==.Soulassassin:BAAALgADCgIJAwAAAA==.Soulhell:BAABLgAECn8cAAIfAAYJaxQ2MQBJAQAfAAYJaxQ2MQBJAQAAAA==.',
Sp='Spartanlofs:BAAALgADCgcJEQAAAA==.Spawndeath:BAAALgADCgEJAQAAAA==.',
Ss='Ssushii:BAAALgAECgEJAQAAAA==.',
St='Staffkiller:BAAALgAECgUJBQAAAA==.Stellån:BAAALgADCgEJAQAAAA==.Stigmata:BAAALgAECgEJAgAAAA==.Stixlightmix:BAABLgAFFH8FAAMbAAMJ5hHKKQCVAAAbAAIJORjKKQCVAAAnAAEJQAWfWgAxAAAAAA==.Stixmixdk:BAABLgAFFH8FAAIXAAMJIhbuLAB7AAAXAAMJIhbuLAB7AAAAAA==.Stixmixwarr:BAAALgAFFAYJAQAAAA==.Straz:BAAALgADCgQJBAAAAA==.Strongman:BAAALgAECgYJBgAAAA==.Stx:BAAALgAECgYJDgAAAA==.',
Su='Subsdk:BAACLgAFFH8VAAIWAAYJpQ8KOAB2AQAWAAYJpQ8KOAB2AQAuAAQKfyQAAxYACAmUHWNDAPEBABYACAmUHWNDAPEBACUAAQnfHzgsAF0AAAAA.Sunwalkers:BAAALgAECgUJBgAAAA==.Supfurry:BAAALgAECgQJBAAAAA==.',
Sw='Swam:BAAALgADCgkJCQAAAA==.Sweetl:BAAALgAECgQJBAAAAA==.',
Sy='Systeni:BAAALgADCgkJCwAAAA==.',
['Sø']='Søøssø:BAAALgAECgYJCAAAAA==.',
Ta='Tacaagua:BAAALgAECgEJAQAAAA==.Taha:BAAALgAECgYJDgAAAA==.Taillys:BAAALgADCgMJBAAAAA==.Tainy:BAAALgAECgEJAQAAAA==.Takemywand:BAAALgADCgUJBQABLgAECgcJFAATAFIQAA==.Takenaka:BAAALgADCgMJAwAAAA==.Tarez:BAAALgAECgkJDgAAAA==.Tarfonir:BAAALgAECgYJCQAAAA==.Tavalira:BAAALgADCgYJBgAAAA==.Taylör:BAAALgADCgEJAQAAAA==.',
Te='Tealen:BAAALgAECgEJAQAAAA==.Ted:BAAALgAECgcJDAAAAA==.Teiseken:BAAALgAECgcJBwAAAA==.Tempesfúria:BAAALgADCgIJAgAAAA==.Tenébria:BAAALgAECgcJBwAAAA==.Teratsemknk:BAAALgAECgUJBQAAAA==.',
Th='Tharnforge:BAAALgAECgEJAQAAAA==.Thejokker:BAACLgAFFH8GAAIQAAMJgQCNRgBkAAAQAAMJgQCNRgBkAAAuAAQKfxcAAhAABwl6BO1iAMEAABAABwl6BO1iAMEAAAAA.Thelaststorm:BAAALgAECgkJAwAAAA==.Themooster:BAABLgAFFH8FAAMDAAMJ7gm0hACOAAADAAIJYg20hACOAAAGAAEJBwOrGQAmAAAAAA==.Thepickles:BAAALgAECgMJAgAAAA==.Thepunk:BAAALgAECgQJEQAAAA==.Thesindorei:BAAALgAECgEJAgAAAA==.Thintor:BAAALgADCgEJAQAAAA==.Thormento:BAABLgAECn8VAAIJAAcJkBFFVQBQAQAJAAcJkBFFVQBQAQAAAA==.Thraell:BAAALgAECgEJAQAAAA==.',
Ti='Tigerblood:BAAALgADCgUJBQAAAA==.Tipooreeii:BAAALgADCgEJAQAAAA==.Titanicos:BAAALgAFFAEJAQAAAA==.',
Tj='Tjhunter:BAABLgAECn8fAAIBAAgJnQpeSQCNAQABAAgJnQpeSQCNAQAAAA==.',
To='Tobbiy:BAABLgAFFH8GAAIXAAMJGhcQHwDfAAAXAAMJGhcQHwDfAAAAAA==.Toddyb:BAAALgAECggJCwAAAA==.Tonytornado:BAAALgAECgEJAgAAAA==.',
Tr='Tranh:BAAALgADCgkJFQAAAA==.Traxer:BAAALgADCgQJBAAAAA==.Tripäsecä:BAAALgAECgcJDgAAAA==.Troladora:BAABLgAECn8VAAIHAAYJqA6cugANAQAHAAYJqA6cugANAQAAAA==.Trévor:BAAALgAECgEJAQAAAA==.',
Ts='Tsreis:BAAALgADCgEJAQAAAA==.',
Tw='Twoheavy:BAAALgADCgkJCQABLgAECgYJCQAIAAAAAA==.',
Ty='Tyrandrisa:BAAALgADCgIJAQAAAA==.',
['Tá']='Tátu:BAAALgADCgMJAwAAAA==.',
Uh='Uhdyr:BAAALgAECgQJBQAAAA==.',
Um='Ummetrodefio:BAAALgADCgEJAQAAAA==.',
Ur='Urthemiel:BAAALgAECgEJAQABLgAECgYJBwAIAAAAAA==.',
Ut='Uthred:BAACLgAFFH8GAAMWAAMJnwFCxACQAAAWAAMJnwFCxACQAAAlAAIJUgCPJAA9AAAuAAQKfzEABBYACQkdBxKQAD0BABYACQnOBBKQAD0BACUABgmqBG8MAOsAABcAAwmuCddGAGYAAAAA.',
Va='Vaelryn:BAAALgAECgYJCQABLgAECgYJBwAIAAAAAA==.Valdemmon:BAAALgAECgQJBwAAAA==.Valororo:BAABLgAECn8YAAIHAAgJUwWvrwAeAQAHAAgJUwWvrwAeAQAAAA==.Vandlesh:BAAALgAECgYJDwAAAA==.Vardha:BAAALgADCgQJBAAAAA==.Varka:BAAALgADCgYJGQAAAA==.',
Ve='Velkharun:BAAALgAECgQJCwABLgAFFAIJBAAIAAAAAA==.Velkryon:BAAALgAECgUJBgAAAA==.Venatrin:BAAALgADCgkJCQAAAA==.Vess:BAAALgAECgQJBAAAAA==.Vexxv:BAABLgAECn8UAAIWAAUJshqnigBrAQAWAAUJshqnigBrAQAAAA==.Vexxz:BAAALgAECgYJBwAAAA==.',
Vi='Viquue:BAAALgADCgYJBgAAAA==.Vivisoft:BAAALgADCgMJAwAAAA==.',
Vl='Vlannytic:BAAALgAECgMJAwAAAA==.',
Vo='Voidrb:BAAALgADCgcJBwABLgAECggJGAAMAAIcAA==.Vovogamer:BAAALgAECgQJBgAAAA==.',
['Vò']='Vòxs:BAACLgAFFH8SAAMMAAQJohTJHgDlAAAMAAMJhxjJHgDlAAAQAAIJug+XPQCTAAAuAAQKf0sAAwwACAk8JLYDAMQCAAwABwnDJLYDAMQCABAABglHHoQuAPcBAAAA.',
Wa='Walkery:BAAALgADCgIJAgAAAA==.Wattari:BAABLgAECn8bAAISAAYJDgR/OACFAAASAAYJDgR/OACFAAAAAA==.Watters:BAAALgAECgUJCwABLgAFFAMJCQAfAJQMAA==.',
Wh='Whiteep:BAAALgADCgYJCAAAAA==.Whiteseraph:BAAALgADCgEJAQAAAA==.Whynchester:BAAALgADCgEJAQAAAA==.',
Wi='Wiilami:BAAALgADCgMJAwAAAA==.Windsailor:BAAALgAECgUJBQAAAA==.Wiserys:BAACLgAFFH8GAAIOAAMJKA4pegDAAAAOAAMJKA4pegDAAAAuAAQKfy8AAw4ACAkKIioYAI0CAA4ACAkrISoYAI0CAA8ABgn+HBMKAK8BAAAA.',
Wm='Wmarcão:BAABLgAECn8YAAMNAAcJbw0gFQDzAAANAAYJlA8gFQDzAAAOAAcJYAX8uQDPAAAAAA==.',
Wo='Wolfiez:BAAALgAECgUJDAAAAA==.Wolfnwar:BAAALgAECgQJDwAAAA==.Wopz:BAAALgADCgcJBwAAAA==.Worq:BAAALgADCgYJBgAAAA==.',
Wq='Wqz:BAABLgAECn8XAAIBAAcJxxmTNgDUAQABAAcJxxmTNgDUAQAAAA==.',
Wu='Wunamuno:BAAALgAECgEJAQAAAA==.',
Xa='Xallatath:BAAALgADCgUJBQAAAA==.Xamela:BAAALgADCgMJAwAAAA==.Xamãna:BAAALgAECgQJCQAAAA==.',
Xb='Xbleidexx:BAAALgADCgYJBgAAAA==.',
Xe='Xevron:BAAALgAECgQJBAAAAA==.Xexnetw:BAAALgAECgQJDQAAAA==.Xexnew:BAABLgAECn8ZAAMXAAkJ9Bp+DgAXAgAXAAkJ9Bp+DgAXAgAWAAEJaQeveAEnAAAAAA==.',
Xf='Xframengox:BAAALgADCgEJAQAAAA==.',
Xi='Xidevill:BAAALgAECgYJEQAAAA==.Xinthorak:BAAALgADCgEJAgAAAA==.Xinzhou:BAAALgADCgQJCAAAAA==.Xiseth:BAAALgAECgIJAgAAAA==.Xixíca:BAAALgADCgUJBgAAAA==.',
Xm='Xmari:BAAALgAECgYJBwAAAA==.',
Xn='Xnyx:BAAALgAECgEJAQAAAA==.',
Xs='Xseth:BAAALgAECgQJBQAAAA==.',
Xu='Xulaman:BAAALgAECgcJDgAAAA==.Xungodz:BAAALgADCgQJBAAAAA==.Xunxu:BAABLgAECn8ZAAMDAAYJdhMQhwBsAQADAAYJdhMQhwBsAQAmAAEJJgM2ngArAAAAAA==.',
Xx='Xxcantsidex:BAAALgAECgEJAQAAAA==.',
Xy='Xynrath:BAAALgADCgMJAwAAAA==.',
['Xÿ']='Xÿon:BAAALgAECgEJAQAAAA==.',
Ya='Yamëte:BAAALgAECgQJBQAAAA==.Yangyung:BAAALgAECgEJAQAAAA==.Yannadcg:BAACLgAFFH8GAAIZAAQJ9gINHwCsAAAZAAQJ9gINHwCsAAAuAAQKfy4AAhkACQmRC/cnAHkBABkACQmRC/cnAHkBAAAA.',
Yo='Yorickundyer:BAAALgAECgIJAwAAAA==.Youdie:BAABLgAECn8YAAIiAAgJhRLwKgCEAQAiAAgJhRLwKgCEAQAAAA==.',
Yu='Yulthuan:BAAALgADCgMJAwAAAA==.',
Yv='Yvernus:BAAALgAECgQJBgAAAA==.',
Yz='Yziepala:BAAALgAECgMJBAAAAA==.',
Za='Zaaraki:BAABLgAECn83AAMWAAkJ6RlLOAAWAgAWAAkJrRhLOAAWAgAXAAcJoRZXIABGAQAAAA==.Zarolho:BAABLgAECn8VAAILAAYJSA6EUAAFAQALAAYJSA6EUAAFAQAAAA==.',
Ze='Zenitsua:BAAALgAECgYJCQAAAA==.Zenzeluk:BAAALgAECgMJAwAAAA==.Zephiir:BAABLgAECn8ZAAIDAAYJExUclwA6AQADAAYJExUclwA6AQAAAA==.Zeroxyz:BAAALgADCgYJBgABLgAECgYJGAAaAJUPAA==.Zeryen:BAAALgAECgEJAQAAAA==.',
Zh='Zhunka:BAAALgADCgEJAgAAAA==.',
Zi='Ziikiipala:BAAALgAECgEJAQAAAA==.',
Zo='Zornak:BAAALgADCgUJBQAAAA==.',
Zz='Zzx:BAAALgADCgcJBwAAAA==.',
['Zé']='Zécasete:BAAALgADCgUJBwAAAA==.',
['Ál']='Álucard:BAABLgAECn8WAAIWAAgJbwocewBkAQAWAAgJbwocewBkAQAAAA==.',
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
