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

local lookup = {'Hunter-BeastMastery','Paladin-Holy','Druid-Restoration','Paladin-Retribution','Druid-Balance','Druid-Feral','Unknown-Unknown','Paladin-Protection','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Fury','Hunter-Survival','Warrior-Protection','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','DemonHunter-Devourer','Monk-Windwalker','DemonHunter-Vengeance','Mage-Arcane','Hunter-Marksmanship','Priest-Shadow','Priest-Discipline','Mage-Fire','Monk-Mistweaver','DemonHunter-Havoc','Druid-Guardian','DeathKnight-Frost','Monk-Brewmaster',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abortheira:BAAALgADCgUJBQAAAA==.',
Ac='Acelord:BAABLgAECn8jAAIBAAkJbxjGJQBLAgABAAkJbxjGJQBLAgAAAA==.Actaeon:BAAALgAECgQJBgAAAA==.',
Ad='Adaar:BAAALgAECgEJAQAAAA==.Adadebox:BAABLgAECn8YAAICAAYJXh9GHQAZAgACAAYJXh9GHQAZAgAAAA==.Adakat:BAAALgADCgEJAQAAAA==.Adanthedark:BAAALgADCgIJAgAAAA==.Adariom:BAAALgADCgUJCAAAAA==.Adilma:BAAALgAECgUJBQAAAA==.Adrian:BAAALgADCgEJAQAAAA==.Adriannos:BAAALgAECgEJAQAAAA==.',
Ae='Aethir:BAAALgADCgYJBwAAAA==.',
Ag='Aghatta:BAAALgAECgcJBwAAAA==.Agonyy:BAAALgAECgUJEAAAAA==.Agrias:BAAALgAECgEJAgAAAA==.',
Ah='Aharadack:BAAALgAECgIJAgAAAA==.',
Ak='Akawaka:BAAALgAECgEJAQAAAA==.Akiji:BAAALgAECgEJBQAAAA==.Akimurad:BAAALgAECgYJBwAAAA==.',
Al='Alakazam:BAAALgADCgcJBwAAAA==.Alanie:BAAALgADCggJCAABLgAECggJJQADABUeAA==.Ald:BAAALgAECgEJAgAAAA==.Aldebaraum:BAAALgAECgcJDQAAAA==.Alexextreme:BAABLgAECn8WAAIBAAcJ8gb+pwDyAAABAAcJ8gb+pwDyAAAAAA==.Aliaksandr:BAAALgAECgEJAQAAAA==.Alikth:BAAALgADCgYJBgAAAA==.Alista:BAAALgAECgQJAwAAAA==.Allandyr:BAACLgAFFH8OAAIBAAMJuxHtXwDlAAABAAMJuxHtXwDlAAAuAAQKf1UAAgEACQnSG2oYAJQCAAEACQnSG2oYAJQCAAAA.Alvarao:BAAALgAECgQJBAAAAA==.',
Am='Amandadark:BAAALgAECgEJAQAAAA==.Amano:BAAALgADCgYJDAAAAA==.',
An='Anaxthacia:BAAALgADCgMJAwAAAA==.Andarilho:BAAALgAECgYJBwAAAA==.Andinth:BAAALgAECgIJAgAAAA==.Andrepvp:BAAALgADCggJDwAAAA==.Andrit:BAAALgADCgEJAQAAAA==.Anelie:BAAALgAECgcJBwABLgAECggJJQADABUeAA==.Anellÿ:BAAALgAECgEJAQAAAA==.Angelloz:BAABLgAECn8rAAIEAAgJARK3fAB1AQAEAAgJARK3fAB1AQAAAA==.Anjelvs:BAAALgAECgYJBgAAAA==.Anksunamoon:BAACLgAFFH8HAAIDAAUJoweSMQDpAAADAAUJoweSMQDpAAAuAAQKfx8ABAMACQkrErBAAI8BAAMACAmRD7BAAI8BAAUABgm4DhU3ADkBAAYAAgk+EFY8AGgAAAAA.Annaoh:BAABLgAECn8cAAIEAAgJVB3TQQABAgAEAAgJVB3TQQABAgAAAA==.Annedin:BAAALgAECgEJAgABLgAECgUJBgAHAAAAAA==.Annia:BAAALgADCgYJBwAAAA==.Anyid:BAAALgAECgMJAwAAAA==.Anãodengoso:BAABLgAECn8pAAMEAAgJSCZgFQDpAgAEAAgJSCZgFQDpAgAIAAIJIxLCPQBmAAABLgAECggJKQAEAEgmAA==.',
Ap='Apökalÿpsïs:BAABLgAECn8vAAIJAAkJdxuSHQCrAgAJAAkJdxuSHQCrAgAAAA==.',
Aq='Aquadel:BAAALgAECgMJAwAAAA==.',
Ar='Arator:BAAALgAECggJDwAAAA==.Ardry:BAAALgADCgYJBgAAAA==.Argaloth:BAAALgAECgYJBwAAAA==.Argonzinha:BAAALgAECgEJAQAAAA==.',
As='Ashryel:BAAALgAECgEJAQAAAA==.Ashthon:BAABLgAECn8eAAIBAAcJgxxINgDVAQABAAcJgxxINgDVAQAAAA==.Asmitta:BAAALgADCgQJBAAAAA==.',
At='Atalantha:BAAALgAECgIJAgAAAA==.Athelass:BAAALgAECgEJAQAAAA==.Atomicdk:BAAALgAECgUJBwAAAA==.Atomictank:BAAALgAECgcJEwAAAA==.Atonos:BAAALgAECgcJDgAAAA==.',
Au='Auquenai:BAAALgADCgUJBQAAAA==.Aurielis:BAAALgAECgEJAgAAAA==.',
Av='Averagemage:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAAALgAECgQJBAAAAA==.',
Az='Azadium:BAAALgAECgUJCgAAAA==.Azul:BAAALgAECgUJCwAAAA==.',
Ba='Baala:BAAALgAECgEJAgAAAA==.Badayaga:BAAALgADCgIJAgAAAA==.Bakunogrind:BAAALgAECgUJBQABLgAFFAQJBwAKAEMeAA==.Balragouldur:BAAALgAECgQJBgAAAA==.Balthar:BAACLgAFFH8HAAQKAAIJqAV8bgBgAAAKAAIJqAV8bgBgAAALAAIJfwI8UQBRAAAMAAEJ5gJuHQA3AAAuAAQKfyAABAsABwk6Ek1KAAsBAAsABwmjEU1KAAsBAAwABAkKEWsdAPUAAAoABAkGD2iqAHQAAAAA.Barathrum:BAAALgAECgEJAQAAAA==.Barcaldas:BAAALgAECgUJBgAAAA==.Barrocø:BAAALgAECgQJBQABLgAECggJGAANAAIcAA==.Basara:BAAALgAECgcJEgAAAA==.Batefraco:BAAALgADCgIJAgAAAA==.',
Bb='Bbiel:BAABLgAECn8nAAMOAAYJnRMAFAAQAQAOAAYJnRMAFAAQAQAPAAQJwQZj7QCFAAAAAA==.',
Be='Beatriz:BAAALgAFFAEJAQAAAA==.Beelgarath:BAAALgAECgYJDgAAAA==.Beherit:BAAALgAECgMJBgAAAA==.Beliall:BAAALgAECgQJBwAAAA==.Belowlight:BAAALgAECgYJEAAAAA==.Belttazar:BAAALgADCgkJDwAAAA==.Bemmaith:BAAALgAECgQJBAAAAA==.Benzema:BAAALgADCgMJAgAAAA==.Berzan:BAAALgAECgUJCwAAAA==.Beyoond:BAACLgAFFH8cAAQPAAUJrxUscQDfAAAPAAMJFBUscQDfAAAQAAIJgBdTIQBPAAAOAAEJ+wccJwBHAAAuAAQKfzoABA8ACQm+HGElAEkCAA8ACQm/G2ElAEkCAA4ABAm3D+cxAPEAABAAAwnBFrwfAMMAAAAA.',
Bh='Bhalin:BAAALgAECgUJCQABLgAECggJKQAEAP4fAA==.',
Bi='Bielinski:BAAALgAECgQJBAAAAA==.Biinarc:BAAALgAECgEJAQAAAA==.',
Bl='Blackdut:BAACLgAFFH8KAAIPAAMJtgQ7DgBhAAAPAAMJtgQ7DgBhAAAuAAQKfxUAAw8ABwmyEWpuAF8BAA8ABwl5EWpuAF8BAA4ABAkpCtQlAIYAAAAA.Blackfear:BAAALgAECgQJBgABLgAFFAMJBwABADMLAA==.Blackrøse:BAAALgADCgYJBgAAAA==.Blackteriaa:BAABLgAECn8UAAIJAAYJ/RNAmgBFAQAJAAYJ/RNAmgBFAQAAAA==.Blacrapumzel:BAAALgAECgMJAwAAAA==.Blakwolf:BAAALgAECgcJDQAAAA==.Blankis:BAAALgADCgYJCQAAAA==.Blastoize:BAAALgAECgQJCAAAAA==.Blizther:BAAALgADCgIJAgAAAA==.Bloodh:BAAALgAECgUJCQAAAA==.Bls:BAAALgADCgMJAwAAAA==.',
Bo='Boijf:BAAALgADCgEJAQAAAA==.Boladomal:BAAALgAECgQJBQAAAA==.Bolt:BAAALgADCgcJBwAAAA==.Bones:BAAALgAECgEJAQAAAA==.Boromy:BAAALgAECgcJDQAAAA==.Boruck:BAAALgAECgIJAwAAAA==.',
Br='Braandom:BAAALgAECgcJEAAAAA==.Bradan:BAABLgAECn8eAAIRAAgJURWcKgAOAgARAAgJURWcKgAOAgAAAA==.Braeon:BAAALgADCgMJAwAAAA==.Brandomm:BAAALgAECgYJDwAAAA==.Branmir:BAAALgAECgMJBgAAAA==.Bridda:BAAALgAECggJEAAAAA==.Brolho:BAAALgADCgEJAQAAAA==.Brusque:BAAALgAECgcJCgAAAA==.Bruzapaladin:BAAALgADCgUJBQAAAA==.',
Bt='Btrcaotics:BAAALgAECgIJCAAAAA==.Btrguard:BAAALgAECgIJAgAAAA==.',
['Bé']='Béto:BAACLgAFFH8FAAIKAAIJVhzLCwBWAAAKAAIJVhzLCwBWAAAuAAQKfxYAAgoACQlfHRkMAPoCAAoACQlfHRkMAPoCAAAA.',
['Bí']='Bíbs:BAABLgAECn8VAAIBAAgJkRPuVgCfAQABAAgJkRPuVgCfAQAAAA==.',
Ca='Cabanagé:BAAALgAECgUJBwAAAA==.Cabeludometa:BAAALgAECgYJDAAAAA==.Cabodecobre:BAAALgAECgUJCwAAAA==.Cainmarko:BAAALgAECgYJEAAAAA==.Caiowisk:BAABLgAECn8eAAMPAAgJNgoijQAgAQAPAAgJSQcijQAgAQAOAAMJZxA5LQBjAAAAAA==.Calir:BAAALgADCgYJFgAAAA==.Calçadora:BAACLgAFFH8GAAISAAIJYxXAKACSAAASAAIJYxXAKACSAAAuAAQKf0EAAhIACQmqIbcFAMoCABIACQmqIbcFAMoCAAAA.Caquinha:BAAALgAECgEJAQAAAA==.Cardrok:BAAALgADCgEJAQAAAA==.Caridosa:BAAALgADCgUJBQAAAA==.Carnius:BAACLgAFFH8MAAMTAAMJmhUGHgCoAAATAAMJmhUGHgCoAAANAAEJDAWBSAAzAAAuAAQKf0QABBMACAlHHmcRANQBABMACAkhHWcRANQBABEAAgm6IAiUAEoAAA0AAQkPHPluAEMAAAAA.Casipala:BAAALgAECgIJAgAAAA==.Casuall:BAAALgAECgcJBwAAAA==.Cataclysm:BAAALgAECgMJBAAAAA==.Catalango:BAAALgAECgQJCgAAAA==.Catapó:BAAALgAFFAIJAwAAAA==.Catapózão:BAABLgAECn8zAAIDAAkJniDHBgBLAwADAAkJniDHBgBLAwAAAA==.Catü:BAAALgAECgEJAQAAAA==.Cavernus:BAAALgADCgMJAwAAAA==.Caves:BAAALgADCgIJAgAAAA==.Caveston:BAAALgADCgUJCgAAAA==.',
Cb='Cbestabr:BAAALgADCgYJBgAAAA==.',
Ch='Chamadmordor:BAAALgAECgMJBQAAAA==.Charats:BAAALgADCgYJDQAAAA==.Charterine:BAAALgADCgYJBgAAAA==.Chaya:BAAALgADCgUJBQAAAA==.Chicknorris:BAAALgADCgUJBQAAAA==.Chifrudaxl:BAAALgAECgMJAwAAAA==.Chrisjks:BAAALgADCgYJCgAAAA==.',
Ci='Cindyn:BAAALgAECgEJAQAAAA==.',
Cl='Clared:BAAALgADCgEJAQAAAA==.Clarkcrente:BAAALgADCgYJBgABLgAECgMJAwAHAAAAAA==.Clebeya:BAAALgADCgQJBAAAAA==.Clebsona:BAAALgAECgIJAgAAAA==.Climps:BAABLgAECn8WAAIBAAgJRRdyPQDrAQABAAgJRRdyPQDrAQAAAA==.',
Co='Cobyx:BAAALgADCgcJDAAAAA==.Cocaferoz:BAAALgADCgEJAQAAAA==.Coffeeaddict:BAAALgADCgMJAwAAAA==.Colugo:BAAALgADCgIJAgAAAA==.Coriisco:BAAALgADCgIJAgAAAA==.Corollaxei:BAABLgAECn83AAQUAAkJsxf1CwAYAgAUAAkJsxf1CwAYAgAVAAYJsQnpSAAHAQAWAAEJWAw2JgAyAAAAAA==.Cosculluela:BAAALgADCgUJBwAAAA==.Cosmuh:BAAALgAECgUJBQAAAA==.',
Cr='Crauwlinhu:BAAALgAECgMJAwAAAA==.Cretaceous:BAAALgADCgEJAQAAAA==.Creuzapriest:BAAALgAECgEJAQAAAA==.Cristïe:BAAALgAECgUJBQAAAA==.Crookedyoung:BAAALgAECgEJAwABLgAECgcJEAAHAAAAAA==.Cruzade:BAABLgAECn8VAAMIAAcJXxDCIwD3AAAIAAYJwBDCIwD3AAAEAAYJdw9M7ADPAAABLgAFFAMJBwABADMLAA==.Cröwllëy:BAACLgAFFH8IAAIXAAMJiw3NqADLAAAXAAMJiw3NqADLAAAuAAQKfyMAAhcACAnZFxVFAPMBABcACAnZFxVFAPMBAAAA.',
Cu='Cubatao:BAABLgAECn8UAAIBAAYJUxTuhwAuAQABAAYJUxTuhwAuAQAAAA==.Cucaracha:BAABLgAECn8YAAIPAAYJVBaXcABZAQAPAAYJVBaXcABZAQAAAA==.',
Da='Dahaka:BAAALgADCgEJAQAAAA==.Dahhak:BAAALgAECgUJCwAAAA==.Dakhgagul:BAAALgADCgUJBQAAAA==.Dakshayani:BAAALgAECgQJBQAAAA==.Dalaigalds:BAAALgAECgEJAQAAAA==.Danielbrz:BAAALgAECgUJBwAAAA==.Daniellpvp:BAAALgADCgEJAQAAAA==.Danygatuxa:BAAALgAECgUJDQAAAA==.Daree:BAAALgAECgEJAQAAAA==.Darkenes:BAAALgAECgEJAQAAAA==.Darkinmt:BAAALgADCgcJCAAAAA==.Darknesstk:BAAALgAECgYJEAAAAA==.Darkowllskul:BAAALgAECgQJCAABLgAECgYJEgAHAAAAAA==.Darksiderptc:BAAALgADCgcJDwAAAA==.Darthmansur:BAAALgAFFAIJBAAAAA==.Dasmithy:BAAALgAECgEJAQAAAA==.',
De='Deadvi:BAABLgAECn8YAAIYAAgJXh02DQA7AgAYAAgJXh02DQA7AgAAAA==.Deadziin:BAABLgAECn8aAAMZAAgJEQiGFwC7AAAZAAcJTAOGFwC7AAAaAAMJFQ+DAwBWAAAAAA==.Deathbringër:BAAALgAECgEJAgAAAA==.Deathheav:BAAALgADCgQJBAAAAA==.Deathivy:BAAALgAECgIJAgAAAA==.Deathmäsk:BAAALgADCgcJBwAAAA==.Defensivepls:BAAALgAECgYJBQAAAA==.Demetrix:BAAALgADCgkJCgAAAA==.Dennyam:BAAALgAECgYJCQAAAA==.Derothey:BAABLgAECn8pAAIJAAgJYBY+WgDPAQAJAAgJYBY+WgDPAQAAAA==.Deservis:BAAALgADCgYJBgAAAA==.Deulorem:BAACLgAFFH8PAAIbAAQJih5DEABRAQAbAAQJih5DEABRAQAuAAQKfz0AAhsACQmBIxQCAIsDABsACQmBIxQCAIsDAAAA.Devilblade:BAABLgAECn8RAAIcAAgJXgmljwACAQAcAAgJXgmljwACAQAAAA==.',
Di='Diabolynn:BAAALgAECgcJEwAAAA==.',
Dk='Dkatraia:BAAALgAECgMJAwAAAA==.',
Dn='Dngfafinir:BAAALgAFFAIJAgABLgAFFAUJDAAEAFgXAA==.Dnghidan:BAACLgAFFH8MAAIEAAUJWBfCRAAiAQAEAAUJWBfCRAAiAQAuAAQKfygAAgQACQmrHvohAKICAAQACQmrHvohAKICAAAA.Dngpain:BAAALgAECgYJDgABLgAFFAUJDAAEAFgXAA==.Dngtobi:BAAALgAECgUJCQABLgAFFAUJDAAEAFgXAA==.',
Do='Dollynhø:BAABLgAECn8nAAIdAAkJFSCDBgDjAgAdAAkJFSCDBgDjAgAAAA==.Donyed:BAAALgAECgUJDAAAAA==.Doomsman:BAAALgADCgUJBQAAAA==.Dottado:BAAALgADCgcJCgAAAA==.',
Dr='Drackah:BAAALgADCgcJBwAAAA==.Draconían:BAAALgAECgEJBwAAAA==.Dracón:BAAALgAECgYJDAAAAA==.Draigo:BAAALgAECgIJAgAAAA==.Dreykar:BAABLgAECn8uAAMcAAkJfBi/IwBBAgAcAAkJfBi/IwBBAgAeAAEJ2BxOLQBNAAAAAA==.Drogorn:BAAALgAECgUJDQAAAA==.Druidaezeki:BAAALgADCgYJCwAAAA==.Druidjm:BAAALgADCgMJAwAAAA==.Druvannar:BAAALgADCgEJAQAAAA==.Dröwränger:BAAALgADCgYJCwAAAA==.',
Du='Dultrasenegl:BAABLgAECn8lAAIBAAYJAA3yZQA2AQABAAYJAA3yZQA2AQAAAA==.Dunois:BAAALgAECgIJBgABLgAECgUJCwAHAAAAAA==.',
['Dä']='Dähäkä:BAABLgAECn8dAAIEAAkJJBtSJAB0AgAEAAkJJBtSJAB0AgAAAA==.',
Ed='Edven:BAACLgAFFH8RAAIUAAMJTAOLJAB5AAAUAAMJTAOLJAB5AAAuAAQKfyEAAhQABgnKDMYlAEgBABQABgnKDMYlAEgBAAAA.',
Ei='Eini:BAAALgAECgEJAgAAAA==.',
El='Elbermt:BAAALgAECgEJAQAAAA==.Elbruxão:BAAALgAECgEJAQAAAA==.Eldrick:BAAALgADCgMJAwAAAA==.Eldros:BAAALgAECgYJCAAAAA==.Elementais:BAABLgAECn8eAAIKAAcJDw/EUABvAQAKAAcJDw/EUABvAQAAAA==.Elgado:BAAALgAECgEJAwAAAA==.Elgatadexota:BAAALgADCgkJCgAAAA==.Eliksir:BAAALgAECgUJBQAAAA==.Ellanor:BAABLgAECn8dAAIJAAgJ+higVQDcAQAJAAgJ+higVQDcAQAAAA==.Ellocopere:BAAALgAECgEJAQAAAA==.Elruth:BAAALgADCggJCAABLgAFFAQJDwAbAIoeAA==.Eltão:BAAALgAECgEJAwAAAA==.Elunah:BAAALgADCgQJBAAAAA==.Elwindor:BAAALgAECgEJAQAAAA==.Elyind:BAAALgADCgYJBwAAAA==.Elyn:BAAALgAECgUJBwAAAA==.',
Em='Emmymm:BAAALgAECgEJAQAAAA==.',
En='Endeavour:BAAALgADCgEJAQAAAA==.Enegadiel:BAABLgAECn8qAAIEAAcJWxXncwCGAQAEAAcJWxXncwCGAQAAAA==.Enoia:BAAALgADCgcJDQAAAA==.',
Eq='Equidnah:BAAALgAECgIJAgAAAA==.',
Er='Erickya:BAAALgAECggJEgAAAA==.Ervadocè:BAABLgAECn8ZAAIFAAYJwhiSNQBBAQAFAAYJwhiSNQBBAQAAAA==.Ervelino:BAAALgAECgMJBAAAAA==.Eryz:BAAALgAECgMJBAAAAA==.',
Es='Esruc:BAAALgAECgEJAQAAAA==.Estrogosbald:BAABLgAECn8ZAAIfAAgJMQzHBgBNAQAfAAgJMQzHBgBNAQAAAA==.',
Eu='Euteinvoco:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.',
Ev='Evely:BAABLgAECn8oAAIgAAgJ2RrxBgAeAgAgAAgJ2RrxBgAeAgAAAA==.',
Ex='Exarch:BAACLgAFFH8NAAISAAQJaRQfFAArAQASAAQJaRQfFAArAQAuAAQKfysAAhIACQm/IYUDAP4CABIACQm/IYUDAP4CAAAA.',
Fa='Faengar:BAAALgAECgUJCAAAAA==.Falcondk:BAAALgAECgEJAQAAAA==.Falconess:BAAALgADCgEJAQAAAA==.Falkorr:BAAALgAECgEJAQAAAA==.',
Fe='Feathria:BAAALgAECgMJAwAAAA==.Felipebritoo:BAAALgAECgMJBgABLgAECgYJEgAHAAAAAA==.Fenrirsp:BAABLgAECn8XAAMhAAgJcyGKGwDoAQAhAAYJpyGKGwDoAQAiAAQJxxrLNQA+AQAAAA==.Ferdruiid:BAAALgADCgkJEwAAAA==.Feropudo:BAAALgADCgkJDgAAAA==.Ferrarig:BAAALgAECgEJBQAAAA==.',
Fi='Figy:BAAALgAECgQJBAAAAA==.Filixy:BAAALgADCgYJBgAAAA==.',
Fl='Flemma:BAABLgAECn8YAAIUAAgJJgfRHQALAQAUAAgJJgfRHQALAQAAAA==.Flexer:BAAALgAECgIJAgAAAA==.Flores:BAAALgADCgMJBgAAAA==.Floridastyle:BAABLgAECn8fAAIiAAUJTxa5NwA0AQAiAAUJTxa5NwA0AQAAAA==.',
Fo='Foguerosa:BAACLgAFFH8JAAMJAAMJpRyQLwD4AAAJAAMJpRyQLwD4AAAjAAEJggBrCAAxAAAuAAQKfxYAAgkACAlpIVREAGsCAAkACAlpIVREAGsCAAAA.Folghunthir:BAAALgADCgQJBAAAAA==.',
Fr='Frankkquini:BAAALgADCgYJEgAAAA==.Friodokrl:BAACLgAFFH8IAAIXAAMJIw4upwDNAAAXAAMJIw4upwDNAAAuAAQKfzYAAxgACQkHHj8PABcCABgACQkuGz8PABcCABcACAkdGt5EAPQBAAAA.Fritzgerhart:BAAALgAECgEJAQAAAA==.Frostkller:BAAALgADCgIJAgAAAA==.Frostmhaw:BAAALgADCgUJBQAAAA==.Frostreaper:BAAALgAECgQJBgAAAA==.',
Fu='Fubukiofhell:BAACLgAFFH8GAAIJAAMJ4xWudwDrAAAJAAMJ4xWudwDrAAAuAAQKfxoAAgkACAnVGVlBABgCAAkACAnVGVlBABgCAAAA.Fuginzao:BAAALgAECgEJAQAAAA==.Furtacor:BAAALgAECgEJAgAAAA==.Furyarh:BAAALgAECgMJAwAAAA==.',
['Fí']='Fí:BAAALgADCggJDgABLgAECgkJHQABALAaAA==.',
Ga='Gabana:BAAALgADCgQJBAAAAA==.Gabdobbuh:BAAALgAECgUJCAAAAA==.Gabn:BAAALgAECgMJBgAAAA==.Gafgar:BAAALgADCgUJCQAAAA==.Gaila:BAAALgAECgIJBgAAAA==.Galduin:BAACLgAFFH8HAAIRAAMJ5wzEOQDMAAARAAMJ5wzEOQDMAAAuAAQKfzQAAhEACQncGbcYACgCABEACQncGbcYACgCAAAA.',
Ge='Gedexx:BAAALgAECgMJAgAAAA==.Geduntruppa:BAAALgAECgYJBgAAAA==.Gentioiroh:BAAALgAECgQJBAAAAA==.',
Gh='Ghorderp:BAAALgADCgcJDAAAAA==.Ghosstt:BAAALgAECgEJAgAAAA==.Ghoulrozon:BAAALgADCgYJBgAAAA==.',
Gi='Giovannapala:BAABLgAECn8aAAIEAAgJiQ72oAA2AQAEAAgJiQ72oAA2AQAAAA==.Giovannasham:BAAALgAECgEJAwAAAA==.Giripoca:BAAALgAECgQJCQAAAA==.',
Gl='Gladsmonge:BAABLgAECn8pAAIkAAcJ3h8GFgBqAgAkAAcJ3h8GFgBqAgAAAA==.Glorcckk:BAAALgAECgUJBQAAAA==.',
Gn='Gnomagga:BAAALgAECgcJEAABLgAECggJNgAIAB8cAA==.Gnomohabe:BAAALgADCgQJBgAAAA==.',
Go='Goddofwarr:BAAALgADCggJEQAAAA==.Gonb:BAAALgADCgUJBQAAAA==.Goueki:BAABLgAECn80AAMBAAgJmBrYMAAYAgABAAgJmBrYMAAYAgAgAAIJSwEtgwA8AAAAAA==.',
Gr='Greenzle:BAAALgAECgUJBgAAAA==.Grillnborst:BAAALgADCgEJAgAAAA==.Grilonp:BAAALgADCgQJCAAAAA==.Grogath:BAAALgAECgQJCAAAAA==.Grogtixa:BAAALgAECggJCQABLgAECgkJKgALAFcWAA==.Gromoff:BAABLgAFFH8HAAIPAAIJwiRXhAC9AAAPAAIJwiRXhAC9AAAAAA==.Grunmonk:BAAALgADCgEJAQAAAA==.Grømmar:BAAALgADCgMJAwAAAA==.',
Gu='Gudangara:BAAALgAECgIJAgAAAA==.Gumy:BAAALgAECgEJBAAAAA==.Guztaverdead:BAAALgADCgQJBAAAAA==.',
['Gü']='Güistrong:BAAALgADCgIJAwAAAA==.',
Ha='Haakaí:BAAALgAECgUJEAAAAA==.Haandir:BAAALgAECgMJBQAAAA==.Hackterin:BAAALgADCgYJBgAAAA==.Hadorah:BAAALgAECgUJBgAAAA==.Haerys:BAAALgAFFAEJAQAAAA==.Handhemirr:BAAALgAECgMJBAAAAA==.Haranclaw:BAAALgAECgEJAQAAAA==.Harany:BAABLgAECn8nAAMiAAgJXRe4EgBOAgAiAAgJXRe4EgBOAgAhAAYJywvFSgDkAAAAAA==.Harrypotinho:BAABLgAECn8yAAIPAAgJch0+JwBAAgAPAAgJch0+JwBAAgAAAA==.Harttas:BAAALgADCgUJBQAAAA==.Haunexd:BAAALgADCgMJAwAAAA==.Havenna:BAAALgAECgUJCAAAAA==.',
He='Headøhunter:BAAALgAECgEJAgAAAA==.Healgate:BAAALgAECgEJAQAAAA==.Heeythaly:BAAALgAECgEJAQAAAA==.Helessa:BAAALgAECgEJAgAAAA==.Hellenah:BAAALgADCggJCAAAAA==.Herablack:BAAALgAECgQJBAAAAA==.Herika:BAAALgADCgMJAwAAAA==.',
Hi='Hidenz:BAAALgAECgIJAgAAAA==.',
Ho='Hoem:BAAALgAECgMJAwAAAA==.Holand:BAAALgAECgYJDAAAAA==.Holydread:BAAALgAECgIJAgAAAA==.',
Hu='Hulig:BAABLgAECn8pAAMEAAgJ/h96JwBmAgAEAAgJ/h96JwBmAgAIAAEJAQfnVAAnAAAAAA==.Hunthearthas:BAAALgAECgMJAwAAAA==.',
['Hø']='Høkulani:BAABLgAECn8dAAIJAAcJchH8iwBfAQAJAAcJchH8iwBfAQAAAA==.',
Ib='Ibrad:BAAALgAECgQJBAAAAA==.Ibuprofens:BAAALgAECgEJAQAAAA==.',
Ic='Iceyag:BAAALgAECgIJAgAAAA==.',
Ig='Igthil:BAAALgADCgYJEAAAAA==.',
Ik='Ikiam:BAAALgAECgUJDAAAAA==.Ikslawok:BAAALgAECgEJAQAAAA==.',
Il='Ileria:BAAALgAECgYJBwAAAA==.Iliriana:BAAALgAECgEJAQAAAA==.Illarion:BAAALgADCgQJBAAAAA==.Illidanos:BAABLgAECn8cAAIlAAgJ/REoIAB4AQAlAAgJ/REoIAB4AQAAAA==.Illidansan:BAAALgAECgQJBQABLgAECgYJCwAHAAAAAA==.Illidris:BAAALgAECgUJBQAAAA==.Illumiinated:BAABLgAECn8UAAImAAYJiwx+RQCSAAAmAAYJiwx+RQCSAAAAAA==.',
In='Incarus:BAAALgAECgcJCgAAAA==.Incognita:BAAALgAECgEJAQAAAA==.Indis:BAAALgADCgQJBgAAAA==.Interst:BAAALgAECgEJAQAAAA==.',
Ir='Irion:BAAALgAECgQJBQAAAA==.',
Is='Iscalio:BAAALgAECgYJCgAAAA==.',
It='Itatchii:BAAALgAECgQJBQAAAA==.',
Iu='Iuuh:BAAALgADCgYJBgAAAA==.',
Iv='Ivinhosilva:BAAALgADCgYJBgAAAA==.',
Ja='Jackdawnsong:BAABLgAECn8aAAIJAAgJiRq2OgAuAgAJAAgJiRq2OgAuAgAAAA==.Jaene:BAAALgADCgYJCQAAAA==.Jahuun:BAABLgAECn8aAAIEAAcJ7Q1VmwA/AQAEAAcJ7Q1VmwA/AQAAAA==.Jamantoso:BAAALgAECgEJAQAAAA==.',
Je='Jeess:BAAALgADCgMJAwAAAA==.Jefflich:BAABLgAECn8iAAMXAAgJ4AqUiQBuAQAXAAgJiwmUiQBuAQAnAAEJhxJpPAAuAAAAAA==.',
Jg='Jg:BAAALgAECgUJBwABLgAECgYJDgAHAAAAAA==.',
Ji='Jinknu:BAAALgAECgIJBAAAAA==.',
Jo='Jottapeg:BAAALgADCgcJAwAAAA==.',
Ju='Jubard:BAAALgADCgkJDAAAAA==.Juliamarques:BAAALgAECgMJBAAAAA==.',
['Jü']='Jüllÿe:BAAALgADCgEJAQAAAA==.',
Ka='Kaaellthas:BAAALgAECgQJDQAAAA==.Kacolux:BAAALgADCgEJAQAAAA==.Kaisaargente:BAAALgAECgEJAQAAAA==.Kakarotho:BAAALgAECgMJCQAAAA==.Kalarath:BAAALgAECgYJBgAAAA==.Kaldonios:BAAALgADCgcJEgAAAA==.Kalma:BAAALgAECgEJAQAAAA==.Kamasutram:BAAALgADCgYJCwAAAA==.Kanadriel:BAAALgAECgcJDAAAAA==.Kanarinho:BAABLgAECn80AAIDAAkJIh/2CAApAwADAAkJIh/2CAApAwAAAA==.Karagume:BAAALgAECgEJAQAAAA==.Karmussie:BAAALgADCgEJAQAAAA==.Karmysh:BAAALgAECgMJAwAAAA==.Katari:BAAALgAECgYJCgABLgAECgkJIAACAAMfAA==.Kayanz:BAAALgADCgUJBQAAAA==.Kazandra:BAAALgADCgYJBgAAAA==.',
Ke='Kendars:BAABLgAECn8VAAQFAAYJ0xKfSAAKAQAFAAUJJhKfSAAKAQADAAUJFQ+5dgDzAAAGAAEJhRUDSwBDAAABLgAFFAMJBwAYALAMAA==.Keox:BAAALgADCgUJBQAAAA==.Ket:BAAALgADCgMJAwAAAA==.',
Kh='Khanmir:BAAALgAECgMJBgAAAA==.Kharon:BAAALgAECgYJBwAAAA==.Khild:BAAALgAECgYJDQAAAA==.Khonar:BAAALgADCgUJBwAAAA==.',
Ki='Killerdek:BAAALgAECgUJBQAAAA==.Killshoty:BAAALgAECgEJAgAAAA==.',
Kl='Klissera:BAAALgADCgQJBAAAAA==.Kluzlocak:BAABLgAECn8iAAIiAAYJUQz7PgAQAQAiAAYJUQz7PgAQAQAAAA==.',
Ko='Komah:BAAALgAECgEJAQAAAA==.Korav:BAAALgAECgMJCQABLgAFFAEJAQAHAAAAAA==.Korium:BAAALgADCgUJBQABLgAECgkJOAATAFckAA==.Koruno:BAAALgADCgYJBgAAAA==.',
Kr='Krosn:BAAALgAECgEJAQAAAA==.Krozhul:BAAALgAECgcJDQAAAA==.Krypthor:BAAALgAECgEJAQAAAA==.',
Ku='Kurnous:BAAALgAECgEJAQAAAA==.Kutirenzo:BAAALgADCgUJBwAAAA==.',
La='Lafiel:BAAALgAECgcJEQAAAA==.Lahllis:BAAALgADCgEJAgAAAA==.Lahnara:BAAALgAECgcJDQAAAA==.Lamelo:BAAALgADCgYJBgAAAA==.Lanjelanje:BAAALgAECgQJBQAAAA==.Lanmo:BAAALgAFFAIJAwAAAA==.Largatixazul:BAAALgADCgUJBgAAAA==.Lataria:BAAALgADCgEJAQAAAA==.Laurea:BAAALgAECgkJEQABLgAECgkJIAACAAMfAA==.',
Le='Ledor:BAAALgAECgEJAgAAAA==.Leebron:BAAALgAECgYJDAAAAA==.Lefthalas:BAAALgAECgUJCgAAAA==.Leitchero:BAAALgAECgIJAgAAAA==.Lemaz:BAAALgAECgEJAQAAAA==.Lemonhunter:BAAALgAECgYJCAAAAA==.Leonelmessi:BAAALgAFFAQJAgAAAA==.Lesco:BAAALgADCgMJAwAAAA==.',
Li='Lianele:BAAALgAECgcJDAAAAA==.Liaras:BAABLgAECn8pAAMbAAgJXBeGHgDRAQAbAAgJXBeGHgDRAQAhAAIJzABFaQAmAAAAAA==.Libertinagem:BAAALgAECgYJDQAAAA==.Lichtbaum:BAABLgAECn8nAAMDAAgJoB1aIABAAgADAAgJoB1aIABAAgAFAAUJwxnROAAwAQAAAA==.Lightsertrop:BAAALgADCgIJAgAAAA==.Liifecomm:BAACLgAFFH8VAAIbAAUJSRR4DgBmAQAbAAUJSRR4DgBmAQAuAAQKfzwAAhsACQl+HlkNAIICABsACQl+HlkNAIICAAAA.Liike:BAAALgAECgcJDQAAAA==.Linestra:BAAALgADCgUJBQAAAA==.Liniak:BAAALgAECgcJEAAAAA==.Lisong:BAAALgAECgIJAgAAAA==.Littlepurple:BAACLgAFFH8JAAIcAAMJzxJ7GwD2AAAcAAMJzxJ7GwD2AAAuAAQKfyQAAhwACQl0HJwYAMICABwACQl0HJwYAMICAAAA.',
Lo='Longhai:BAAALgADCgUJCAAAAA==.Lookatmylock:BAABLgAECn8iAAMOAAYJ/xu1DAB0AQAOAAYJ/xu1DAB0AQAPAAIJmBFLHQFLAAAAAA==.Lordpain:BAAALgAECggJDgAAAA==.Lortherti:BAAALgAECgIJAgAAAA==.Lorwin:BAABLgAECn8UAAIBAAgJhBmaSgDBAQABAAgJhBmaSgDBAQAAAA==.Lotusbr:BAAALgADCgEJAQAAAA==.Louisenacioo:BAABLgAECn8UAAMUAAcJUhCMFQB0AQAUAAcJUhCMFQB0AQAVAAMJqwXdewBpAAAAAA==.Loátrak:BAAALgADCgMJAwAAAA==.',
Lu='Luanne:BAAALgADCgEJAQAAAA==.Luccablack:BAAALgAECgQJBwAAAA==.Luccagelido:BAAALgAECgUJCQAAAA==.Lucyx:BAAALgAECgIJAgAAAA==.Luidar:BAAALgAECgQJBAAAAA==.Lukaslions:BAABLgAECn8gAAIRAAkJaA8TLACkAQARAAkJaA8TLACkAQAAAA==.Lukathan:BAAALgADCgQJBAAAAA==.Lunarie:BAAALgAECgYJEwABLgAECgcJBwAHAAAAAA==.Luphoe:BAABLgAECn8nAAMDAAcJ9RzHJwAWAgADAAcJ9RzHJwAWAgAFAAQJkw4fZACLAAAAAA==.Luxanä:BAAALgAECgYJBgAAAA==.',
['Lé']='Léio:BAAALgADCgcJCAAAAA==.Léora:BAAALgADCgIJAgAAAA==.',
['Lø']='Lørdsith:BAAALgAECgYJCAABLgAECggJBgAHAAAAAA==.',
['Lÿ']='Lÿcäns:BAAALgADCgMJAwAAAA==.',
Ma='Madagalux:BAABLgAECn8rAAIQAAgJQQr5DwBfAQAQAAgJQQr5DwBfAQAAAA==.Madalenna:BAAALgAECgMJBQAAAA==.Madjack:BAAALgAECgMJAwAAAA==.Madushi:BAAALgAFFAEJAQAAAA==.Madzerø:BAAALgAECgEJBAAAAA==.Magatiun:BAAALgADCgMJBAAAAA==.Magogunt:BAABLgAECn8kAAIJAAkJMxHDVADeAQAJAAkJMxHDVADeAQAAAA==.Maguul:BAABLgAECn8ZAAIIAAgJ5hWZEQCrAQAIAAgJ5hWZEQCrAQAAAA==.Magzifeh:BAABLgAECn8UAAIBAAcJ3SAmOwDyAQABAAcJ3SAmOwDyAQAAAA==.Mahadevi:BAAALgADCgIJAgAAAA==.Mahdemon:BAAALgAECgYJCQAAAA==.Maiconhood:BAAALgAFFAEJAQAAAA==.Malaks:BAAALgADCgMJAwAAAA==.Malandrvs:BAAALgAFFAEJAwAAAA==.Maljamim:BAAALgADCgIJAgAAAA==.Mamuthwar:BAABLgAECn8ZAAMRAAcJnRgeNgDQAQARAAcJnRgeNgDQAQANAAEJMQ7ZQQA1AAAAAA==.Mandingavudu:BAAALgAECgYJBwABLgAFFAEJAQAHAAAAAA==.Manei:BAAALgAECgMJAwAAAA==.Mangalarga:BAAALgADCgEJAQAAAA==.Manmoden:BAAALgADCgUJBQABLgAFFAEJAQAHAAAAAA==.Mannatur:BAABLgAECn8bAAMFAAkJ6hxnEgBDAgAFAAgJ3xtnEgBDAgAmAAgJahf5EQDQAQABLgAFFAEJAQAHAAAAAA==.Manopaladino:BAAALgADCgYJBgAAAA==.Manowlo:BAAALgAECgMJAwAAAA==.Manzagon:BAAALgAECgYJCQABLgAFFAEJAQAHAAAAAA==.Marandracon:BAAALgADCgMJAwAAAA==.Marmelo:BAAALgADCgQJBAAAAA==.Marretasanta:BAABLgAECn8kAAIEAAcJCRR5jwBTAQAEAAcJCRR5jwBTAQAAAA==.Maruterrestr:BAAALgAECgMJAgAAAA==.Marù:BAAALgAECgYJCwAAAA==.Marúh:BAACLgAFFH8SAAIKAAUJPRjrIgBjAQAKAAUJPRjrIgBjAQAuAAQKfykAAgoACQmQIMQFABYDAAoACQmQIMQFABYDAAAA.Matroná:BAAALgADCggJBwAAAA==.Maxmorf:BAAALgADCgUJBQAAAA==.Mayarabr:BAAALgAECgYJDwAAAA==.Mazeratos:BAAALgAECgMJBQAAAA==.',
Mc='Mcorelhao:BAAALgADCgEJAQAAAA==.',
Me='Medoza:BAAALgAECgQJBgAAAA==.Megrezz:BAAALgAECgEJAQAAAA==.Mehiel:BAAALgAECgEJAQAAAA==.Mekihlvshtak:BAAALgAECgYJBwAAAA==.Meliøðas:BAAALgADCgEJAQAAAA==.Mendingu:BAABLgAECn8YAAMNAAgJAhwEGwCDAQARAAgJRxgYKAAdAgANAAQJ/CAEGwCDAQAAAA==.Mercenarybr:BAAALgAECgEJAgAAAA==.Merumim:BAAALgAECgYJCwAAAA==.Metalgirl:BAAALgADCgYJCwAAAA==.Methamorfo:BAAALgADCggJCQAAAA==.',
Mi='Midrão:BAAALgAFFAEJAQAAAA==.Miisuky:BAAALgADCgUJBAAAAA==.Mikasaackerr:BAAALgAECgEJAgAAAA==.Milczarek:BAAALgAECgEJAwAAAA==.Mindlocker:BAABLgAECn8dAAIPAAcJMwmjkwAUAQAPAAcJMwmjkwAUAQAAAA==.Minorus:BAAALgAFFAIJAgAAAA==.Mirager:BAAALgAECgQJBAAAAA==.Mistifs:BAABLgAECn8pAAIkAAgJ5R1tDwCsAgAkAAgJ5R1tDwCsAgAAAA==.Miticamais:BAAALgAECgQJBQAAAA==.',
Mo='Modogz:BAAALgADCgYJBgAAAA==.Momongadk:BAAALgADCgcJBwAAAA==.Monkeydking:BAAALgADCgUJBQAAAA==.Morania:BAABLgAECn8XAAIOAAgJUwbpFwDiAAAOAAgJUwbpFwDiAAAAAA==.Mordekais:BAAALgAECgIJAgAAAA==.Morganne:BAAALgAECgEJAQAAAA==.Morinami:BAAALgAECgQJBwAAAA==.Moriyama:BAABLgAECn8rAAMDAAkJKx0yIQA+AgADAAgJXxwyIQA+AgAFAAIJExJvbABxAAAAAA==.Morphez:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Morphisz:BAAALgAFFAEJAQAAAA==.Morphiszs:BAAALgAECgMJBQABLgAFFAEJAQAHAAAAAA==.Morphizs:BAAALgAECgEJBAABLgAFFAEJAQAHAAAAAA==.Mortesan:BAAALgAECgEJAQABLgAECgYJCwAHAAAAAA==.',
Mp='Mpastor:BAAALgADCgUJBQAAAA==.',
Mu='Muca:BAAALgADCgEJAQAAAA==.Muho:BAAALgADCgEJAQAAAA==.Mukonha:BAABLgAECn8jAAIPAAcJeA4LjQAgAQAPAAcJeA4LjQAgAQAAAA==.',
My='Myzukim:BAAALgADCgUJBQAAAA==.',
['Mã']='Mãoleves:BAAALgADCgEJAQAAAA==.',
['Må']='Måximus:BAAALgAECgUJCQAAAA==.',
['Mü']='Müller:BAAALgADCgEJAQABLgAECgcJEAAHAAAAAA==.',
Na='Naeryndam:BAAALgADCgEJAQAAAA==.Namyara:BAAALgAECgEJAQAAAA==.Narutowow:BAAALgADCgMJAwAAAA==.Natcmd:BAAALgADCggJJQAAAA==.Nathilell:BAAALgADCgIJAgAAAA==.Naturezo:BAAALgAECgUJCAAAAA==.Navira:BAAALgAECgEJAQAAAA==.Nayanna:BAAALgADCgcJDQAAAA==.Nazzd:BAAALgAECgQJBAABLgAECgUJBQAHAAAAAA==.',
Ne='Negblack:BAACLgAFFH8HAAIBAAMJswoeawDOAAABAAMJswoeawDOAAAuAAQKfxQAAgEABwlLDYGAAD4BAAEABwlLDYGAAD4BAAAA.Neggi:BAAALgAECgUJBwAAAA==.Nemesysy:BAAALgAECgMJAwAAAA==.Nerphien:BAAALgADCgUJBQAAAA==.Nesktpally:BAAALgAECgcJCAAAAA==.Netbrood:BAAALgADCgUJBgABLgAECgUJBwAHAAAAAA==.Netbrother:BAAALgAECgUJBwAAAA==.Nethdorai:BAAALgADCgQJBAAAAA==.Netherbane:BAABLgAECn81AAMNAAgJLx3MDQAMAgANAAgJLx3MDQAMAgARAAIJGQ9GpAAxAAAAAA==.Nezuko:BAAALgAECgUJBQABLgAECggJMgAPAHIdAA==.',
Ni='Niar:BAAALgAECgQJBQAAAA==.Nightmære:BAAALgAECgQJCwAAAA==.Nikelina:BAAALgAECgEJAQAAAA==.Nikelok:BAABLgAECn8ZAAIPAAcJfgfqogD6AAAPAAcJfgfqogD6AAAAAA==.Ninfador:BAABLgAECn8eAAIiAAYJgxeqMQBVAQAiAAYJgxeqMQBVAQAAAA==.Ninpus:BAAALgAECgMJAwAAAA==.',
No='Noobmasteer:BAAALgADCgIJAgAAAA==.Nooneknow:BAACLgAFFH8HAAIXAAQJTBUTlADkAAAXAAQJTBUTlADkAAAuAAQKfzkAAhcACQlUIUUWAMECABcACQlUIUUWAMECAAAA.Nosios:BAAALgAECgYJBgAAAA==.Nosrede:BAAALgAECgEJAQAAAA==.Notz:BAAALgADCgMJBAAAAA==.',
Nu='Nucciwarrior:BAAALgAECgUJCAAAAA==.Nuccixama:BAAALgAECgcJCQAAAA==.',
Ny='Nyde:BAAALgAECgMJAwAAAA==.',
['Nø']='Nøar:BAAALgADCgIJAgAAAA==.',
Oa='Oakshlar:BAAALgAFFAEJAQAAAA==.',
Oc='Ocelaris:BAAALgAECgEJAgAAAA==.',
Oh='Ohlu:BAAALgAECgYJCQAAAA==.Ohluh:BAAALgAECgcJDQAAAA==.',
Or='Ormagh:BAAALgADCgYJBgAAAA==.Oryana:BAAALgAECgEJAQAAAA==.Oríon:BAAALgADCgIJAgAAAA==.',
Ot='Otton:BAABLgAECn8pAAIEAAgJYQktuwAPAQAEAAgJYQktuwAPAQAAAA==.',
Ov='Overnigth:BAAALgADCgIJAgAAAA==.Overwalker:BAAALgAECgEJAgAAAA==.Ovosemdente:BAAALgADCgEJAQAAAA==.',
Ow='Owllskull:BAAALgAECgYJEgAAAA==.',
Oz='Ozovo:BAAALgAECgcJEgAAAA==.',
Pa='Pacoka:BAAALgADCgQJBQAAAA==.Padrafferty:BAAALgADCgcJBwAAAA==.Paidesanto:BAABLgAECn8WAAQQAAcJyhAZGwDlAAAQAAYJKg8ZGwDlAAAPAAYJMgt/0gCwAAAOAAMJ5RGTRgCcAAAAAA==.Paidesantox:BAABLgAECn8YAAIFAAcJRAkDRQD4AAAFAAcJRAkDRQD4AAABLgAFFAMJBwARAOcMAA==.Paidocharles:BAAALgAECgIJBQAAAA==.Paladinokun:BAAALgAECgYJCwAAAA==.Palanis:BAAALgAECgcJBwAAAA==.Palazarta:BAABLgAECn8XAAIEAAcJBAqRvgAKAQAEAAcJBAqRvgAKAQAAAA==.Pandavoli:BAAALgAECgUJDAAAAA==.Pangolinho:BAAALgAECgQJBgAAAA==.Panky:BAAALgAECgQJBAAAAA==.Panquecudo:BAAALgADCgIJAgAAAA==.',
Pd='Pdois:BAAALgADCgMJAwAAAA==.',
Pe='Pesscador:BAAALgAECgMJAwAAAA==.Petrolesk:BAAALgAECgYJEwAAAA==.',
Pi='Piriguetee:BAAALgADCgEJAQAAAA==.Pirro:BAAALgAECgEJAQAAAA==.Pisadinha:BAAALgADCgcJBwAAAA==.',
Pk='Pkzimn:BAAALgADCgUJBQAAAA==.',
Pl='Playsson:BAAALgAECgYJEgAAAA==.Plottwist:BAAALgADCgcJDwABLgAECgkJOQAXAOEaAA==.',
Po='Pogonus:BAAALgADCgIJAgAAAA==.Pontocego:BAAALgAECgQJBAAAAA==.Pororocaa:BAAALgAECgQJCAAAAA==.Posturado:BAAALgADCgEJAQAAAA==.Powerworth:BAAALgAECgEJAQAAAA==.',
Pr='Pravios:BAAALgAECggJDgAAAA==.Priestkill:BAAALgADCgcJCQAAAA==.Prikithon:BAAALgAECgEJAQAAAA==.Primewolf:BAAALgAECgMJAwAAAA==.',
Ps='Psicomanic:BAAALgADCgMJAwAAAA==.',
Pt='Pterodactilo:BAAALgAECgYJAQAAAA==.',
Pu='Puherito:BAAALgAECgUJDAAAAA==.Purgas:BAAALgAFFAEJAQAAAA==.',
Qu='Quartohokage:BAAALgADCgEJAQAAAA==.Quinthalam:BAAALgADCgMJAwAAAA==.',
Ra='Rafac:BAAALgAECgEJAgABLgAFFAEJAQAHAAAAAA==.Rafazinho:BAAALgADCgQJBAAAAA==.Ramyna:BAAALgAECgMJBQAAAA==.Ramyra:BAAALgADCgcJDQAAAA==.Raphaeldh:BAAALgAECgEJAgAAAA==.Raphahunterr:BAAALgADCgEJAQAAAA==.Raposa:BAAALgADCgEJAQAAAA==.Raposinha:BAAALgADCgMJAwAAAA==.Rarkway:BAAALgAECgcJCwAAAA==.Ravenblak:BAAALgADCgMJAwAAAA==.Rayanne:BAAALgADCgYJBgAAAA==.Raycujoh:BAAALgADCgEJAQAAAA==.',
Re='Reckfull:BAAALgAECgYJBgAAAA==.Regininha:BAAALgAECgEJAQAAAA==.Reloumifrend:BAAALgAECgcJCgAAAA==.Rendros:BAAALgADCgUJBQAAAA==.',
Rh='Rhaegaar:BAAALgAECgcJDQAAAA==.Rhanideri:BAAALgADCgEJAQAAAA==.Rhodinius:BAAALgAECgMJCAAAAA==.',
Ri='Rivotreel:BAAALgADCgQJBAAAAA==.',
Ro='Robeerth:BAABLgAFFH8HAAIBAAMJMwsehACTAAABAAMJMwsehACTAAAAAA==.Rochera:BAAALgAECgEJAQAAAA==.Rokhanar:BAAALgAECgUJCwAAAA==.',
Ru='Rudemonster:BAAALgAECgEJAQAAAA==.Ruhtarr:BAAALgADCgEJAQAAAA==.',
Ry='Ryukato:BAAALgAECgQJBQAAAA==.',
Sa='Saek:BAAALgAECgcJEgAAAA==.Saelor:BAAALgAECgEJAgAAAA==.Sakurachan:BAAALgADCgUJBQAAAA==.Sanderclone:BAAALgAECgEJAQAAAA==.Sanguenafaca:BAAALgADCgYJCgAAAA==.Santiss:BAABLgAECn8WAAIEAAYJDhWYqQApAQAEAAYJDhWYqQApAQAAAA==.Santorini:BAAALgAECgcJDQAAAA==.Saphirot:BAAALgADCgUJBQAAAA==.Saphis:BAAALgADCgEJAQAAAA==.Sardado:BAAALgAECgEJAQAAAA==.Sardron:BAAALgAECgEJAQAAAA==.',
Sc='Scanorr:BAAALgAECgYJDAAAAA==.Scheffers:BAABLgAECn8YAAIhAAYJwRMpNgA9AQAhAAYJwRMpNgA9AQAAAA==.',
Se='Selah:BAAALgADCgQJBgAAAA==.Selver:BAAALgAECgcJCAABLgAFFAcJGgAhALAaAA==.Selüne:BAAALgAECgcJDQAAAA==.Sephora:BAAALgAECgYJCwABLgAECggJKQAbAFwXAA==.Sevagoth:BAAALgAECggJDQAAAA==.',
Sh='Shadowlock:BAAALgADCgIJAQABLgAECgYJFAAcAN8UAA==.Shadowmornac:BAAALgAECgMJBgAAAA==.Shallkiller:BAAALgADCgIJBAAAAA==.Shamanica:BAAALgAECgEJAgAAAA==.Shamateus:BAAALgADCggJEwAAAA==.Shasuna:BAAALgADCgIJAgAAAA==.Shaunnun:BAAALgADCgEJAQAAAA==.Shenloong:BAAALgADCgYJBgAAAA==.Shieldhonor:BAAALgADCgUJBQAAAA==.Shinnók:BAAALgAECgIJAgAAAA==.Shiíro:BAAALgAFFAIJBAABLgAFFAUJEwAEABAkAA==.Shynato:BAAALgADCgEJAQAAAA==.Shynock:BAAALgADCgEJAQAAAA==.Shyriull:BAAALgAECgEJAQAAAA==.Shyzuno:BAAALgADCgQJBAAAAA==.Shãka:BAAALgADCgMJAwAAAA==.',
Si='Siladriel:BAAALgADCgMJAwAAAA==.Silfirrion:BAAALgADCgEJAQABLgAECgkJPAAOAIEfAA==.Silvanna:BAAALgAECgQJBAAAAA==.Silvao:BAAALgADCgIJBAAAAA==.Sirgonzo:BAABLgAECn8XAAIEAAkJtxdvPgAMAgAEAAkJtxdvPgAMAgAAAA==.',
Sk='Skullexus:BAAALgAECgMJBAAAAA==.Skunkbr:BAAALgADCgEJAQAAAA==.',
Sl='Sleepychety:BAAALgAECgUJBgAAAA==.Slowsmoke:BAAALgADCgYJBwAAAA==.Slyfer:BAABLgAFFH8GAAIBAAIJwRQ5gACYAAABAAIJwRQ5gACYAAAAAA==.',
Sn='Snatzz:BAAALgADCgMJAgAAAA==.',
So='Soggoth:BAAALgADCgkJCQAAAA==.Solk:BAAALgAECgMJBgAAAA==.Sontarfury:BAAALgAECgEJAQAAAA==.Soray:BAAALgAECgUJBgAAAA==.Sorim:BAABLgAECn8qAAIDAAgJ0hstHABlAgADAAgJ0hstHABlAgAAAA==.Soryan:BAABLgAECn8rAAMDAAgJeBXVLwDkAQADAAgJeBXVLwDkAQAFAAUJ+g3qUADKAAAAAA==.Soulassassin:BAAALgADCgIJAwAAAA==.Soulhell:BAABLgAECn8cAAIiAAYJaxQcNQBBAQAiAAYJaxQcNQBBAQAAAA==.',
Sp='Spartanlofs:BAAALgADCgcJEQAAAA==.Spawndeath:BAAALgADCgEJAQAAAA==.Spezia:BAAALgAECgQJBQAAAA==.',
Ss='Ssushii:BAAALgAECgEJAQAAAA==.',
St='Staffkiller:BAAALgAECggJEgAAAA==.Stellån:BAAALgADCgcJCAAAAA==.Stigmata:BAAALgAECgEJAgAAAA==.Stixlightmix:BAABLgAFFH8FAAMdAAMJ5hFYLgCPAAAdAAIJORhYLgCPAAAoAAEJQAWdXwAxAAAAAA==.Stixmixdk:BAABLgAFFH8FAAIYAAMJIhaHMgByAAAYAAMJIhaHMgByAAAAAA==.Stixmixwarr:BAAALgAFFAYJAQAAAA==.Straz:BAAALgADCgQJBAAAAA==.Strongman:BAAALgAECgYJBgAAAA==.Stx:BAAALgAECgYJDgAAAA==.',
Su='Subsdk:BAACLgAFFH8VAAIXAAYJpQ8QQwBvAQAXAAYJpQ8QQwBvAQAuAAQKfyYAAxcACAkeHsxAAAECABcACAkeHsxAAAECACcAAQnfH6wwAFsAAAAA.Sunwalkers:BAAALgAECgUJBgAAAA==.Supfurry:BAAALgAFFAIJAgAAAA==.Suushy:BAAALgAECgQJBgAAAA==.',
Sw='Swam:BAAALgADCgkJCQAAAA==.Sweetl:BAAALgAECgQJBAAAAA==.',
Sy='Syreenaa:BAAALgAECgEJAQAAAA==.Systeni:BAAALgADCgkJCwAAAA==.',
['Sä']='Säek:BAAALgAECgIJAgAAAA==.',
['Sø']='Søøssø:BAAALgAECgYJCAAAAA==.',
Ta='Tacaagua:BAAALgAECgIJAgAAAA==.Taha:BAAALgAECgYJDgAAAA==.Taillys:BAAALgADCgMJBAAAAA==.Tainy:BAAALgAECgEJAQAAAA==.Takemywand:BAAALgADCgUJBQABLgAECgcJFAAUAFIQAA==.Takenaka:BAAALgADCgMJAwAAAA==.Tarez:BAAALgAECgkJDgAAAA==.Tarfonir:BAAALgAECgYJCQAAAA==.Tashian:BAAALgADCgIJAgAAAA==.Tavalira:BAAALgADCgYJBgAAAA==.Taylör:BAAALgADCgEJAQAAAA==.',
Te='Tealen:BAAALgAECgEJAQAAAA==.Ted:BAAALgAECgcJDAAAAA==.Teiseken:BAAALgAECgcJBwAAAA==.Telaskei:BAAALgAECgUJBQAAAA==.Tempesfúria:BAAALgADCgIJAgAAAA==.Tenébria:BAAALgAECgcJBwAAAA==.Teratsemknk:BAAALgAECgUJBQAAAA==.',
Th='Tharnforge:BAAALgAECgEJAQAAAA==.Thejokker:BAACLgAFFH8HAAIRAAMJ8AAXTABvAAARAAMJ8AAXTABvAAAuAAQKfxcAAhEABwl6BKFoALwAABEABwl6BKFoALwAAAAA.Themooster:BAABLgAFFH8IAAMIAAMJmA4REgBrAAAEAAIJYg2kkgCOAAAIAAIJBBAREgBrAAAAAA==.Thepickles:BAAALgAECgUJCQAAAA==.Thepunk:BAAALgAECgQJEQAAAA==.Thesindorei:BAAALgAFFAEJAQAAAA==.Thintor:BAAALgADCgEJAQAAAA==.Thormento:BAABLgAECn8VAAIKAAcJkBGZWgBOAQAKAAcJkBGZWgBOAQAAAA==.Thraell:BAAALgAECgEJAQAAAA==.Threeß:BAAALgAECgQJBQAAAA==.',
Ti='Tigerblood:BAAALgADCgUJBQAAAA==.Tipooreeii:BAAALgADCgEJAQAAAA==.Titanicos:BAAALgAFFAIJAgAAAA==.',
Tj='Tjhunter:BAABLgAECn8fAAIBAAgJnQpeSQCNAQABAAgJnQpeSQCNAQAAAA==.',
To='Tobbiy:BAABLgAFFH8IAAIYAAMJWxihIgDXAAAYAAMJWxihIgDXAAAAAA==.Toddyb:BAAALgAECggJCwAAAA==.Tonytornado:BAAALgAECgEJAgAAAA==.',
Tr='Tranh:BAAALgADCgkJFQAAAA==.Traxer:BAAALgADCgQJBAAAAA==.Tripäsecä:BAAALgAECgcJDgAAAA==.Troladora:BAABLgAECn8VAAIJAAYJqA7xwwAEAQAJAAYJqA7xwwAEAQAAAA==.Trévor:BAAALgAECgEJAQAAAA==.',
Ts='Tsreis:BAAALgADCgEJAQAAAA==.',
Tu='Tutydias:BAAALgAECgMJAwAAAA==.',
Tw='Twoheavy:BAAALgADCgkJCQABLgAECgYJCQAHAAAAAA==.',
Ty='Tyrandrisa:BAAALgADCgIJAQAAAA==.',
['Tá']='Tátu:BAAALgADCgMJAwAAAA==.',
Uh='Uhdyr:BAAALgAECgQJBQAAAA==.',
Um='Ummetrodefio:BAAALgADCgEJAQAAAA==.',
Ur='Urthemiel:BAAALgAECgEJAQABLgAECgYJBwAHAAAAAA==.',
Ut='Uthred:BAACLgAFFH8GAAMXAAMJnwGL1wCKAAAXAAMJnwGL1wCKAAAnAAIJUgASKwA8AAAuAAQKfzEABBcACQkdB1uaADUBABcACQnOBFuaADUBACcABgmqBG8MAOsAABgAAwmuCbdKAGMAAAAA.',
Va='Vaelryn:BAAALgAECgYJCQABLgAECgYJBwAHAAAAAA==.Valdemmon:BAAALgAECgQJBwAAAA==.Valororo:BAABLgAECn8bAAIJAAkJtAYDjgBbAQAJAAkJtAYDjgBbAQAAAA==.Vandlesh:BAABLgAECn8WAAIJAAcJBw01pwAvAQAJAAcJBw01pwAvAQAAAA==.Vardha:BAAALgADCgQJBAAAAA==.Varka:BAAALgADCgYJGQAAAA==.',
Ve='Velkharun:BAAALgAECgQJDAABLgAFFAMJBwABADMLAA==.Velkryon:BAAALgAECgUJBgAAAA==.Veltharyn:BAAALgAECgEJAQAAAA==.Venatrin:BAAALgADCgkJCQAAAA==.Vess:BAAALgAECgQJBAAAAA==.Vexxv:BAABLgAECn8UAAIXAAUJshqnigBrAQAXAAUJshqnigBrAQAAAA==.Vexxz:BAAALgAECgYJCAAAAA==.',
Vi='Viquue:BAAALgADCgYJBgAAAA==.Vivisoft:BAAALgADCgMJAwAAAA==.',
Vl='Vlannytic:BAAALgAECgMJAwAAAA==.',
Vo='Voidrb:BAAALgADCgcJBwABLgAECggJGAANAAIcAA==.Vovogamer:BAAALgAECgQJBgAAAA==.',
['Vò']='Vòxs:BAACLgAFFH8SAAMNAAQJohSrIwDhAAANAAMJhxirIwDhAAARAAIJug/fQwCSAAAuAAQKf0sAAw0ACAk8JLYDAMQCAA0ABwnDJLYDAMQCABEABglHHoQuAPcBAAAA.',
Wa='Walkery:BAAALgADCgIJAgAAAA==.Wattari:BAABLgAECn8bAAITAAYJDgTOOwCEAAATAAYJDgTOOwCEAAAAAA==.Watters:BAAALgAECgUJCwABLgAFFAMJCwAiAGENAA==.',
Wh='Whiteep:BAAALgADCgYJCAAAAA==.Whiteseraph:BAAALgADCgEJAQAAAA==.Whynchester:BAAALgADCgEJAQAAAA==.',
Wi='Wiilami:BAAALgADCgMJAwAAAA==.Windsailor:BAAALgAECgUJBQAAAA==.Wiserys:BAACLgAFFH8GAAIPAAMJKA5chAC9AAAPAAMJKA5chAC9AAAuAAQKfzIAAw8ACAkSI4YWAJ0CAA8ACAk0IoYWAJ0CABAABgn+HBsLAKwBAAAA.',
Wm='Wmarcão:BAABLgAECn8YAAMOAAcJbw2WFgDwAAAOAAYJlA+WFgDwAAAPAAcJYAXkwgDHAAAAAA==.',
Wo='Wolfiez:BAAALgAECgUJDAAAAA==.Wolfnwar:BAAALgAECgQJEAAAAA==.Wopz:BAAALgADCgcJBwAAAA==.Worq:BAAALgADCgYJBgAAAA==.',
Wq='Wqz:BAABLgAECn8XAAIBAAcJxxmTNgDUAQABAAcJxxmTNgDUAQAAAA==.',
Wu='Wunamuno:BAAALgAECgEJAQAAAA==.',
Xa='Xallatath:BAAALgADCgUJBQAAAA==.Xamela:BAAALgADCgMJAwAAAA==.Xamãna:BAAALgAECgQJCQAAAA==.',
Xb='Xbleidexx:BAAALgADCgYJBgAAAA==.',
Xe='Xevron:BAAALgAECgQJBAAAAA==.Xexnetw:BAAALgAECgQJDQAAAA==.Xexnew:BAACLgAFFH8FAAIYAAIJLg6sNgBbAAAYAAIJLg6sNgBbAAAuAAQKfxkAAxgACQn0GuEPAA0CABgACQn0GuEPAA0CABcAAQlpB5WQAScAAAAA.',
Xf='Xframengox:BAAALgADCgEJAQAAAA==.',
Xi='Xidevill:BAABLgAECn8cAAIlAAYJJwiBPgC8AAAlAAYJJwiBPgC8AAAAAA==.Xinthorak:BAAALgADCgEJAgAAAA==.Xinzhou:BAAALgADCgQJCAAAAA==.Xiseth:BAAALgAECgIJAgAAAA==.Xixíca:BAAALgADCgUJBgAAAA==.',
Xl='Xladymaladax:BAAALgAECgEJAQAAAA==.',
Xm='Xmari:BAAALgAECgYJBwAAAA==.',
Xn='Xnyx:BAAALgAECgQJBAAAAA==.',
Xo='Xots:BAAALgADCgMJAwAAAA==.',
Xs='Xseth:BAAALgAECgYJBwAAAA==.',
Xu='Xulaman:BAAALgAECgcJDgAAAA==.Xungodz:BAAALgADCgQJBAAAAA==.Xunxu:BAABLgAECn8ZAAMEAAYJdhMQhwBsAQAEAAYJdhMQhwBsAQACAAEJJgM2ngArAAAAAA==.',
Xx='Xxcantsidex:BAAALgAECgcJCAAAAA==.',
Xy='Xynrath:BAAALgADCgMJAwAAAA==.',
['Xÿ']='Xÿon:BAAALgAECgEJAQAAAA==.',
Ya='Yamëte:BAAALgAECgYJCQAAAA==.Yangyung:BAAALgAECgEJAQAAAA==.Yannadcg:BAACLgAFFH8GAAIbAAQJ9gJaIgCoAAAbAAQJ9gJaIgCoAAAuAAQKfy4AAhsACQmRCyEqAHcBABsACQmRCyEqAHcBAAAA.',
Yo='Yorickundyer:BAAALgAECgUJCAAAAA==.Youdie:BAABLgAECn8YAAIhAAgJhRLwKgCEAQAhAAgJhRLwKgCEAQAAAA==.',
Yu='Yulthuan:BAAALgADCgMJAwAAAA==.',
Yv='Yvernus:BAAALgAECgQJBgAAAA==.',
Yz='Yziepala:BAAALgAECgMJBAAAAA==.',
Za='Zaaraki:BAABLgAECn85AAMXAAkJ4RrDNAAsAgAXAAkJpBnDNAAsAgAYAAcJoRYJIgBCAQAAAA==.Zarolho:BAABLgAECn8VAAILAAYJSA6EUAAFAQALAAYJSA6EUAAFAQAAAA==.',
Ze='Zenitsua:BAAALgAECgYJCQAAAA==.Zenzeluk:BAAALgAECgMJAwAAAA==.Zephiir:BAABLgAECn8jAAIEAAYJIxgzBADsAAAEAAYJIxgzBADsAAAAAA==.Zeroxyz:BAAALgADCgYJBgABLgAECgYJGAAcAJUPAA==.Zeryen:BAAALgAECgEJAQAAAA==.',
Zh='Zhunka:BAAALgADCgEJAwAAAA==.',
Zi='Ziikiipala:BAAALgAECgIJAwAAAA==.',
Zo='Zornak:BAAALgADCgUJBQAAAA==.',
Zz='Zzx:BAAALgADCgcJBwAAAA==.',
['Zé']='Zécasete:BAAALgADCgUJBwAAAA==.',
['Ál']='Álucard:BAABLgAECn8XAAIXAAgJtgyqdQB4AQAXAAgJtgyqdQB4AQAAAA==.',
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
