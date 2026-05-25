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

local lookup = {'Druid-Balance','Warrior-Arms','Warrior-Fury','Mage-Frost','Mage-Arcane','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Druid-Restoration','Warrior-Protection','Hunter-Survival','Priest-Discipline','Warlock-Demonology','Monk-Brewmaster','Rogue-Subtlety','Evoker-Augmentation','Evoker-Devastation','Rogue-Outlaw','Shaman-Enhancement','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Preservation','DemonHunter-Vengeance','Rogue-Assassination','DemonHunter-Devourer','Hunter-BeastMastery','Druid-Feral','DeathKnight-Frost','Paladin-Protection','Priest-Holy','DemonHunter-Havoc','Hunter-Marksmanship','Druid-Guardian','Mage-Fire',}
local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Aberdus:BAABLgAECn8YAAIBAAcJJRW2KwBIAQABAAcJJRW2KwBIAQAAAA==.',
Ac='Accalon:BAABLgAECn8jAAMCAAgJcxhQEADAAQACAAgJGBhQEADAAQADAAIJixBMawB7AAABLgAECggJHwAEAOAYAA==.',
Ad='Adina:BAAALgAECgYJBgAAAA==.Advacus:BAACLgAFFH8UAAMEAAUJahdsRAA9AQAEAAUJYRRsRAA9AQAFAAIJ6hUVAwBVAAAuAAQKfyUAAwUACAlmH/8BAJACAAUACAmWGv8BAJACAAQACAkEHEZQAEYCAAAA.',
Ai='Aicila:BAAALgADCgEJAQAAAA==.Aimer:BAAALgAECgEJAQAAAA==.Airi:BAAALgADCgYJCAABLgAECgEJAQAGAAAAAA==.',
Ak='Akrama:BAABLgAECn8tAAMHAAkJuRxvFQA5AgAHAAkJuRxvFQA5AgAIAAYJdAmlwQDiAAAAAA==.',
Al='Alara:BAAALgADCgkJEwAAAA==.Alatáriel:BAAALgAECgIJAgAAAA==.Alectrona:BAAALgAECgQJBwAAAA==.Aletriss:BAAALgAECgYJEwAAAA==.Alexsham:BAAALgAECgEJAQAAAA==.Algaraz:BAAALgAECgYJDgAAAA==.',
Am='Ama:BAAALgAECgQJBQAAAA==.Amnorpse:BAABLgAECn8iAAIDAAgJrR+cDgBmAgADAAgJrR+cDgBmAgAAAA==.',
An='Anabana:BAAALgAECgQJCwAAAA==.Angler:BAABLgAECn8gAAMJAAkJCBo2DACjAgAJAAkJCBo2DACjAgAKAAEJrAVZlAAkAAAAAA==.Anruu:BAAALgAECgUJBQAAAA==.',
Ap='Appollis:BAAALgAECgEJAQAAAA==.Appropriate:BAAALgADCgMJAwAAAA==.',
Ar='Araleth:BAAALgAECgMJAwAAAA==.Arkthurus:BAAALgAECgYJDQAAAA==.Artumis:BAAALgADCgEJAQAAAA==.Arvitherejet:BAAALgAECgYJDgAAAA==.',
As='Aschern:BAAALgAECgYJDAAAAA==.Ashenfang:BAAALgAECgQJBAAAAA==.Ashijin:BAACLgAFFH8UAAIIAAUJdhpAIQBRAQAIAAUJdhpAIQBRAQAuAAQKfycAAggACQlVIREmAI4CAAgACQlVIREmAI4CAAAA.Ashilyn:BAAALgAECgEJAQAAAA==.Ashoo:BAAALgADCgEJAQAAAA==.Astei:BAAALgADCgEJAQAAAA==.',
At='Ataxxius:BAAALgADCgMJAwAAAA==.Atheristina:BAAALgAECgQJCQABLgAECgcJHAALALUbAA==.Atroce:BAAALgAECgQJBwAAAA==.Atticu:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAABLgAECn8/AAIHAAkJPRmxEQBjAgAHAAkJPRmxEQBjAgAAAA==.Auxilium:BAABLgAECn8cAAIIAAkJohXRSAAIAgAIAAkJohXRSAAIAgAAAA==.',
Aw='Awnen:BAABLgAECn8XAAIMAAYJNgo0KwC2AAAMAAYJNgo0KwC2AAAAAA==.',
Az='Aza:BAAALgADCgIJAgAAAA==.',
Ba='Backtrakk:BAAALgADCgMJAwAAAA==.Baelsson:BAAALgAECgkJCAAAAA==.Bahndis:BAAALgADCgcJDAAAAA==.Balebrew:BAAALgAFFAIJAgAAAA==.Balethar:BAAALgAECgYJEwABLgAFFAIJAgAGAAAAAA==.Ballador:BAAALgAECggJEQAAAA==.Balluh:BAABLgAECn81AAINAAgJYBfHFADkAQANAAgJYBfHFADkAQAAAA==.',
Be='Bearforceone:BAAALgAECgEJAQAAAA==.Beartest:BAAALgAECgMJBAABLgAFFAUJCgAOAIkJAA==.Beezen:BAACLgAFFH8TAAIKAAYJfBmfBgB7AQAKAAYJfBmfBgB7AQAuAAQKfyUAAgoACAm/IUcFADADAAoACAm/IUcFADADAAAA.Belara:BAAALgADCgYJBwAAAA==.Bellevo:BAAALgAECgQJBAABLgAECgkJKQAEAFMfAA==.Bellmage:BAABLgAECn8pAAMEAAkJUx8jFgC5AgAEAAkJUx8jFgC5AgAFAAEJxAlqHwAxAAAAAA==.Belttoash:BAABLgAECn8vAAIIAAcJQh3CRQDWAQAIAAcJQh3CRQDWAQAAAA==.Beneficiary:BAAALgAECgQJBQAAAA==.Bercey:BAABLgAECn8eAAIPAAkJwA5gQwC5AQAPAAkJwA5gQwC5AQAAAA==.Beybladetest:BAACLgAFFH8GAAMKAAMJRw2PHgCwAAAKAAMJxQiPHgCwAAAQAAIJkw+LGwCQAAAuAAQKfyAABBAACQkVGgEWAFoCABAACAnmGgEWAFoCAAoABAmSGQU7AOcAAAkABAlQCshiAI4AAAEuAAUUBQkKAA4AiQkA.',
Bi='Bigmang:BAAALgADCgYJBgAAAA==.Bigmayex:BAAALgADCgkJFgABLgAECgkJGgARAMsaAA==.Bigscott:BAAALgAECgMJAwABLgAFFAUJBwAIAGkNAA==.Bilmuri:BAAALgAECgUJCAAAAA==.Binky:BAAALgADCgIJAgAAAA==.',
Bl='Blackbride:BAAALgAECgMJAwAAAA==.Blackfyre:BAAALgAECgIJBAAAAA==.Blackmage:BAAALgAFFAEJAQAAAA==.Blastknight:BAAALgAECgIJAgABLgAFFAUJEQADAGsfAA==.Blizzdrood:BAAALgAECgUJCwABLgAECggJNAAPAM8UAA==.Blizzlock:BAABLgAECn80AAIPAAgJzxTlPwDFAQAPAAgJzxTlPwDFAQAAAA==.Blood:BAAALgAECgIJBAAAAA==.Bloodfeast:BAAALgADCgYJBgAAAA==.Blooms:BAAALgADCgIJAgAAAA==.Blurednuhtz:BAAALgADCgYJCQAAAA==.',
Bo='Bobcatross:BAAALgADCgYJBgAAAA==.Bohvicce:BAAALgADCgEJAQAAAA==.Bokudo:BAAALgADCgMJAwAAAA==.Bonezs:BAABLgAECn9HAAMLAAkJFiOdBABZAwALAAkJFiOdBABZAwABAAUJvhOWPwDeAAAAAA==.Boogiepop:BAAALgAECgcJEwAAAA==.Bootylika:BAABLgAECn8bAAIDAAgJkxWiLgD3AQADAAgJkxWiLgD3AQAAAA==.Borislav:BAAALgADCgEJAQAAAA==.Bossvega:BAAALgAECgUJCAAAAA==.Boutdatbass:BAAALgAECgYJEwAAAA==.',
Br='Braxxar:BAABLgAECn8XAAIIAAcJdw1OiwA5AQAIAAcJdw1OiwA5AQAAAA==.Brendelf:BAAALgADCgcJCQAAAA==.Brett:BAAALgAECgEJAgAAAA==.Briellia:BAAALgAECgYJDgAAAA==.Brightaf:BAAALgADCgkJCQAAAA==.Bruggerlock:BAEALgADCgMJAwAAAA==.Bruhkakke:BAAALgAECgcJBgABLgAFFAYJDwAOAPsQAA==.Bryagh:BAABLgAECn8oAAMSAAgJDhZVHgDCAQASAAgJDhZVHgDCAQATAAIJnwwiNwBfAAAAAA==.',
Bu='Bubbam:BAAALgADCgYJCAAAAA==.Bufferbug:BAAALgADCgkJFAAAAA==.Bugbear:BAAALgAECgcJDAAAAA==.Bulge:BAAALgADCgUJBQABLgAECggJGwAUAN8bAA==.Bullycow:BAABLgAECn8XAAIVAAYJJgXhGgAbAQAVAAYJJgXhGgAbAQAAAA==.Bushybrowsy:BAABLgAECn8qAAQWAAkJyhJ4BgDfAQAWAAkJyhJ4BgDfAQAPAAcJSwjoigAPAQAXAAMJRwJ5XQBWAAAAAA==.Buttercupz:BAABLgAECn8dAAIYAAkJlgthIwCFAQAYAAkJlgthIwCFAQAAAA==.',
['Bá']='Bámboo:BAAALgAECgEJAQAAAA==.',
['Bî']='Bîgdaddy:BAABLgAECn8nAAMZAAkJCBdMGABbAgAZAAkJCBdMGABbAgAaAAQJmgNqagCaAAAAAA==.',
Ca='Cacho:BAAALgAECggJCgAAAA==.Calevan:BAAALgAECgkJDwAAAA==.Candoran:BAAALgADCgMJAwAAAA==.Caracarn:BAAALgAECgcJDAAAAA==.Carpulations:BAABLgAECn8XAAIPAAYJEBivhABQAQAPAAYJEBivhABQAQAAAA==.Catty:BAAALgAECgMJAwAAAA==.',
Cc='Ccyll:BAAALgADCgkJEgAAAA==.',
Ce='Cerofewol:BAAALgADCgMJAwABLgAECgUJBwAGAAAAAA==.Cerokos:BAAALgADCgUJBQAAAA==.Cerridwen:BAABLgAECn8aAAIOAAYJ6AkpNAAXAQAOAAYJ6AkpNAAXAQAAAA==.',
Ch='Chantini:BAAALgAECgUJBQAAAA==.Chartreuze:BAAALgAECgQJBgAAAA==.Chazmonk:BAAALgAECgEJAQABLgAFFAMJCAAZACQOAA==.Chazzie:BAACLgAFFH8IAAIZAAMJJA70PAC8AAAZAAMJJA70PAC8AAAuAAQKfxgAAhkACQl0G3YMAM0CABkACQl0G3YMAM0CAAAA.Cheonsul:BAAALgADCgQJBgAAAA==.Chexmix:BAAALgADCgUJBwAAAA==.Chia:BAACLgAFFH8YAAMbAAYJURQAJQCDAQAbAAUJURQAJQCDAQAcAAEJAACsTQAAAAAuAAQKfyQAAhsACAlXHzYwABsCABsACAlXHzYwABsCAAAA.Chikn:BAABLgAECn8XAAIJAAgJ8xRYGAD7AQAJAAgJ8xRYGAD7AQAAAA==.Chirichiri:BAAALgADCgIJBAAAAA==.Chizu:BAAALgADCgUJBQABLgAFFAUJGAADAMogAA==.Chomboslice:BAABLgAECn8oAAMHAAkJXBxfEgB/AgAHAAkJXBxfEgB/AgAIAAYJFRFqmgAfAQAAAA==.',
Cl='Clary:BAAALgAECgEJAQABLgAECggJIAAQALIZAA==.Classy:BAAALgAECgYJBwAAAA==.',
Cm='Cmil:BAACLgAFFH8VAAMHAAYJzxKcDACqAQAHAAYJzxKcDACqAQAIAAIJyAGEfABpAAAuAAQKfx8AAwcACAnxC8k4AJcBAAcACAnxC8k4AJcBAAgAAQnODcpCATMAAAAA.',
Co='Coffeebrew:BAAALgAECgcJDwAAAA==.Coffeecrem:BAAALgAECgcJDQABLgAECgcJDwAGAAAAAA==.Coffeelune:BAAALgAECgEJAQAAAA==.Coffie:BAAALgADCgUJBQABLgAECgcJDwAGAAAAAA==.Coldnoodles:BAAALgAECgMJAwABLgAFFAMJCAAKAJUZAA==.Combat:BAACLgAFFH8RAAIDAAUJARhqCwBKAQADAAUJARhqCwBKAQAuAAQKfx4AAgMACAk/HkoVAKMCAAMACAk/HkoVAKMCAAAA.Cornish:BAECLgAFFH8cAAIJAAYJFCJwBQBPAgAJAAYJFCJwBQBPAgAuAAQKfzUAAwkACQkDJM4BAKADAAkACQkDJM4BAKADAAoABQlPGYIyABEBAAAA.Cornishpaste:BAEALgAECgQJBAABLgAFFAYJHAAJABQiAA==.Cosmo:BAAALgADCgcJCQABLgAECgkJFQAKAC8YAA==.',
Cr='Crackjaw:BAAALgAECgMJBgAAAA==.Crakmybitzup:BAAALgAECgUJBQAAAA==.Crockodk:BAAALgAECgEJAQAAAA==.',
Cu='Curserodlock:BAAALgAECgcJDwAAAA==.',
Cy='Cyanide:BAAALgAECgYJBwAAAA==.',
Da='Dabbinshamin:BAAALgAECgkJDwAAAA==.Dadanbing:BAAALgAECgYJBgABLgAFFAMJCQAZAEMPAA==.Daddyomg:BAAALgAECgYJCAABLgAFFAcJJAAaAH8bAA==.Dads:BAACLgAFFH8kAAMaAAcJfxuwCQCoAQAaAAYJZhmwCQCoAQAZAAQJKQitPAC8AAAuAAQKfxsAAxoACQkWJSMQAKgCABoABwm6JCMQAKgCABkACQloF74iAA4CAAAA.Daggertest:BAAALgADCgQJBAABLgAFFAUJCgAOAIkJAA==.Dahai:BAAALgAECgMJAwAAAA==.Dakeyras:BAABLgAECn8iAAMMAAkJBBvUBwBfAgAMAAkJBBvUBwBfAgADAAMJIAR7iQAzAAAAAA==.Danzon:BAAALgAECgEJAQAAAA==.Darcevoker:BAACLgAFFH8MAAIdAAUJTwhYDAAiAQAdAAUJTwhYDAAiAQAuAAQKfyQAAh0ACAmrGOoNAFkCAB0ACAmrGOoNAFkCAAAA.Darcmonk:BAABLgAFFH8FAAIJAAQJgwRIJQDJAAAJAAQJgwRIJQDJAAABLgAFFAUJDAAdAE8IAA==.Darcpaladin:BAAALgAECgQJBQABLgAFFAUJDAAdAE8IAA==.Darcshaman:BAAALgAECgIJAgABLgAFFAUJDAAdAE8IAA==.Darkrune:BAABLgAECn8ZAAIbAAYJuhpabQBlAQAbAAYJuhpabQBlAQAAAA==.Darkschneide:BAAALgAECgQJBQAAAA==.Darthboo:BAAALgADCggJDAAAAA==.Darthtemplar:BAAALgAECgQJBAAAAA==.Davris:BAAALgAECgUJCAAAAA==.',
Db='Dbmagic:BAAALgAECgcJDwAAAA==.',
De='Dealsun:BAABLgAECn8bAAMPAAgJdBObRAD+AQAPAAgJdBObRAD+AQAXAAUJ2QdIOADTAAAAAA==.Decynth:BAAALgAECgcJCQAAAA==.Defne:BAAALgAECgEJBQAAAA==.Demodorn:BAECLgAFFH8cAAIeAAUJGwdrAgCvAAAeAAUJGwdrAgCvAAAuAAQKfy0AAh4ACAm1Fk4IAPgBAB4ACAm1Fk4IAPgBAAAA.Demondudez:BAAALgAECgUJCwAAAA==.Demonikat:BAAALgADCgEJAQAAAA==.Demonsurfin:BAAALgAECgUJBQAAAA==.Demussi:BAAALgAECgEJAQAAAA==.Demyst:BAACLgAFFH8XAAMZAAUJxw+uFQBwAQAZAAUJxw+uFQBwAQAaAAUJlRDjGwASAQAuAAQKfyEAAxoACQlZHykSAJICABoACQlZHykSAJICABkAAgmmDTytADgAAAAA.Deria:BAAALgAECgEJAQAAAA==.Devilsparda:BAAALgAECgMJAwAAAA==.Deweey:BAAALgAECgcJEAAAAA==.Dezeraz:BAECLgAFFH8MAAIdAAQJbBwYBwB+AQAdAAQJbBwYBwB+AQAuAAQKfyMAAh0ACAkDJv4BAFsDAB0ACAkDJv4BAFsDAAEuAAUUBgkcAAkAFCIA.',
Dh='Dhecaye:BAAALgAECgEJAQABLgAFFAQJBQAJAPoKAA==.',
Di='Dieuscum:BAAALgAECgUJBQAAAA==.Diksneeze:BAAALgADCgUJCAAAAA==.Disengage:BAAALgAECgkJAwABLgAFFAUJEQADAAEYAA==.Dislogic:BAABLgAECn8kAAMPAAkJciLhDADQAgAPAAgJciLhDADQAgAXAAQJTSCiGwBwAQAAAA==.',
Dl='Dlorpglorp:BAAALgAECgIJAgABLgAECggJIQAEALgfAA==.',
Do='Dobbie:BAAALgADCgUJBQAAAA==.Donkey:BAAALgAECgcJCgAAAA==.Donmega:BAAALgAECgMJAwAAAA==.Doraleous:BAABLgAECn8pAAIHAAkJbR3tCwCqAgAHAAkJbR3tCwCqAgAAAA==.Dotzmybitzup:BAACLgAFFH8OAAMPAAQJmx6HHgAKAQAPAAQJmx6HHgAKAQAXAAEJRQ3iHgBGAAAuAAQKfzYABA8ACAmQJSwMANcCAA8ACAmQJSwMANcCABYAAglqEzEdAIgAABcAAQlXDm9jAEgAAAEuAAUUBgkSABIAhhgA.Dougalleone:BAACLgAFFH8VAAIRAAUJoyJDEABXAQARAAUJoyJDEABXAQAuAAQKfyUAAxEACQmJIocHABgDABEACQmJIocHABgDAB8AAQmtEfsdAD0AAAAA.',
Dr='Draci:BAAALgADCgEJAQAAAA==.Drdumbottles:BAAALgAECgYJBgAAAA==.Dreadknott:BAACLgAFFH8KAAIbAAMJFxAdggDQAAAbAAMJFxAdggDQAAAuAAQKfzIAAhsACQleHfIiAFcCABsACQleHfIiAFcCAAAA.Dreadxknight:BAAALgADCgMJAwAAAA==.Drekim:BAABLgAECn8UAAISAAUJryAbLgBRAQASAAUJryAbLgBRAQAAAA==.Dreko:BAAALgAECgQJBgAAAA==.Drezzakmage:BAACLgAFFH8KAAIEAAQJMwgVVQAbAQAEAAQJMwgVVQAbAQAuAAQKfyIAAgQACQlcFl9gABoCAAQACQlcFl9gABoCAAAA.Drezzakzdh:BAAALgADCgYJBgABLgAFFAQJCgAEADMIAA==.Druidiac:BAAALgADCgYJEwABLgAECgkJLQAYAIYaAA==.',
Du='Dugren:BAAALgAECgkJCQAAAA==.',
Ed='Edgelf:BAAALgADCgMJAwAAAA==.',
El='Elaidare:BAAALgAFFAMJAwAAAA==.Elaidine:BAABLgAECn8aAAMeAAgJiw06EAAcAQAeAAgJiw06EAAcAQAgAAEJAACaFwEAAAABLgAFFAMJAwAGAAAAAA==.Elisabetta:BAAALgADCgMJAwAAAA==.Elizalex:BAAALgAECgIJBAAAAA==.',
Em='Emagdne:BAAALgADCgMJAgAAAA==.Empath:BAAALgADCgQJBQAAAA==.',
En='Enferno:BAAALgAECgYJDgABLgAECggJNAAPAM8UAA==.Enfernum:BAAALgADCgEJAQABLgAECggJNAAPAM8UAA==.Enolad:BAAALgADCgcJBwABLgAECgcJDAAGAAAAAA==.Entrapy:BAAALgAECgEJAQAAAA==.',
Er='Eradius:BAAALgAECgUJBQAAAA==.Errai:BAABLgAECn80AAIPAAkJOSFtDgDCAgAPAAkJOSFtDgDCAgAAAA==.',
Es='Estefania:BAAALgAECgEJAQAAAA==.',
Eu='Eureka:BAABLgAECn8gAAIBAAkJ/xmaCwB1AgABAAkJ/xmaCwB1AgAAAA==.',
Ev='Evilnapkin:BAAALgAECgQJEQAAAA==.Evion:BAABLgAECn8gAAIhAAkJchuRGwBXAgAhAAkJchuRGwBXAgAAAA==.',
Ey='Eyedoll:BAAALgAECgEJAQAAAA==.Eyez:BAAALgADCgIJAgAAAA==.',
Fa='Faelthorn:BAAALgADCgQJBAAAAA==.Faemalis:BAAALgAECgEJAQAAAA==.Farseer:BAAALgADCgMJAwAAAA==.',
Fe='Feardoctor:BAAALgAECgUJCQAAAA==.Feelthepower:BAABLgAECn8WAAIEAAYJ2xi5jwA9AQAEAAYJ2xi5jwA9AQAAAA==.',
Fl='Flavorfrenzy:BAAALgADCgUJBQABLgAECgkJQQAcANokAA==.',
Fo='Fourimborniy:BAAALgAECgcJCwAAAA==.',
Fr='Frenzi:BAAALgADCgEJAQAAAA==.Friendulum:BAAALgAECgcJBwAAAA==.Fries:BAEALgAECgEJAQABLgAFFAQJBwAPAKYPAA==.Frostey:BAAALgADCgEJAQAAAA==.',
Fu='Fuzzsicle:BAAALgAECgYJCQAAAA==.Fuzzydìcê:BAAALgAECgUJCAAAAA==.',
['Fá']='Fáelen:BAABLgAECn8fAAIiAAgJOB6pBgCLAgAiAAgJOB6pBgCLAgAAAA==.',
Ga='Galang:BAAALgAECgMJBQAAAA==.Gangactivity:BAAALgAECgQJCwABLgAFFAMJCQAKAPkcAA==.Garm:BAAALgAECgEJBAAAAA==.Garrt:BAABLgAECn8aAAIiAAcJdxoyCwDUAQAiAAcJdxoyCwDUAQAAAA==.Gartalvanise:BAAALgAECgkJDwAAAA==.Gartarrior:BAAALgADCgYJBgAAAA==.Gartt:BAAALgADCgEJAQAAAA==.Gavinrad:BAAALgAECggJEwAAAA==.',
Ge='Gelato:BAAALgADCgEJAgAAAA==.Gep:BAABLgAECn8UAAIIAAcJ9SHAOgD4AQAIAAcJ9SHAOgD4AQAAAA==.',
Gi='Gilene:BAAALgADCgYJAQAAAA==.',
Gl='Glaalinix:BAAALgADCgkJGgAAAA==.Glaciiel:BAAALgAECgMJAwAAAA==.Globbie:BAAALgADCgMJAwAAAA==.',
Go='Goku:BAAALgAECgcJCgAAAA==.Goobman:BAAALgADCgQJBQABLgAFFAUJDQALANgYAA==.Goodman:BAABLgAECn8tAAIIAAkJ+R0EGgCJAgAIAAkJ+R0EGgCJAgAAAA==.Goomei:BAACLgAFFH8SAAIKAAQJfh2ABwBuAQAKAAQJfh2ABwBuAQAuAAQKfzIAAgoACQmnIrUDAAcDAAoACQmnIrUDAAcDAAEuAAUUCAkdACAAJhoA.Goomi:BAACLgAFFH8dAAIgAAgJJhqeBABkAgAgAAgJJhqeBABkAgAuAAQKfyMAAiAACQmWIxADAJ4DACAACQmWIxADAJ4DAAAA.Gordius:BAAALgADCgEJAQAAAA==.Gorok:BAAALgAECgQJCgAAAA==.Goybeam:BAAALgADCgcJCQAAAA==.',
Gr='Gravykin:BAABLgAECn8WAAIiAAkJcQ35DgCQAQAiAAkJcQ35DgCQAQAAAA==.Grayfoxrun:BAAALgADCgUJBQAAAA==.Greatbooty:BAABLgAECn8iAAIEAAgJKxnlQQD7AQAEAAgJKxnlQQD7AQAAAA==.Grecko:BAAALgADCgUJBQAAAA==.Gremmi:BAAALgAECgEJBgAAAA==.Greygavel:BAABLgAECn8VAAIjAAgJQCOLAgCiAgAjAAgJQCOLAgCiAgAAAA==.Grimmknight:BAAALgADCgEJAQAAAA==.Grishypally:BAAALgAECgkJAQAAAA==.Grosgland:BAAALgADCgEJAQAAAA==.Groundbeéf:BAACLgAFFH8WAAIVAAYJHCJiAQCxAQAVAAYJHCJiAQCxAQAuAAQKfykAAhUACAkJJvsAAH4DABUACAkJJvsAAH4DAAAA.Groundzero:BAAALgADCgUJBQAAAA==.Groztrazztok:BAAALgAECgYJEwAAAA==.Grungulus:BAAALgAECgcJEwAAAA==.',
Gu='Guineapig:BAEBLgAECn8UAAIIAAcJLyTdMABfAgAIAAcJLyTdMABfAgAAAA==.Gundral:BAAALgADCgIJAgAAAA==.Gunnysack:BAAALgADCggJDgAAAA==.Guzmo:BAAALgAECgEJAQABLgAECgUJBgAGAAAAAA==.',
Gy='Gyx:BAAALgAECgQJCAAAAA==.',
Ha='Haiku:BAAALgAECgEJAQAAAA==.Handanir:BAABLgAECn80AAILAAkJYCG7BQBEAwALAAkJYCG7BQBEAwAAAA==.Harie:BAABLgAECn8mAAIEAAgJJA7bbQCCAQAEAAgJJA7bbQCCAQAAAA==.Hasbula:BAAALgAECgQJBAAAAA==.Hatebound:BAAALgAECgIJAgAAAA==.',
He='Hearthcliff:BAAALgAECgQJDQAAAA==.Heihei:BAAALgADCgYJDAAAAA==.Heiny:BAACLgAFFH8KAAMjAAMJSSFxCgAJAQAjAAMJbh1xCgAJAQAbAAMJ2xqQaQD2AAAuAAQKfyIABCMACQlOJjgBAAkDACMACQk7JDgBAAkDABsACAlvJrkLAPECABwABgkEET8mAA0BAAAA.Heinyheinyho:BAACLgAFFH8GAAIHAAMJDhu2IgDbAAAHAAMJDhu2IgDbAAAuAAQKfy4AAwcACAk+JLIIAOQCAAcACAk+JLIIAOQCACQABQk6ISYSAHcBAAEuAAUUAwkKACMASSEA.',
Hi='Hielle:BAAALgADCgkJCQAAAA==.Highguard:BAAALgADCgcJBwAAAA==.Himothy:BAAALgAECgEJBAAAAA==.',
Ho='Hoid:BAAALgAECgEJAgAAAA==.Holy:BAAALgADCgYJBgAAAA==.Holysword:BAEALgADCgYJBgABLgAECgQJBQAGAAAAAA==.Holytest:BAABLgAFFH8KAAMOAAUJiQkzFgBmAQAOAAUJiQkzFgBmAQAlAAUJmAEkEwD/AAAAAA==.Hoofmetoo:BAABLgAECn8yAAMjAAgJtR+mBAA9AgAjAAgJIBumBAA9AgAbAAgJvx0CLgAkAgAAAA==.Howboudah:BAAALgADCggJCAAAAA==.',
Hu='Hulkgirl:BAAALgADCgEJAQAAAA==.Hulzar:BAABLgAECn8YAAIDAAcJlRzPIgC3AQADAAcJlRzPIgC3AQAAAA==.',
Hy='Hypocrisy:BAAALgAECgkJBgAAAA==.',
['Hô']='Hôlyblight:BAAALgAECgEJAQABLgAFFAUJEwAaAHIYAA==.',
Ic='Iceflare:BAABLgAECn8ZAAMEAAgJihbfVAA5AgAEAAgJihbfVAA5AgAFAAQJ7gLmEwCHAAAAAA==.',
Id='Idotyouto:BAABLgAECn8vAAIEAAgJnhvSUgA/AgAEAAgJnhvSUgA/AgAAAA==.',
Ig='Igris:BAAALgAECgQJDgAAAA==.',
Ih='Ihavewater:BAAALgADCgkJDgAAAA==.',
Ik='Iktizi:BAAALgADCgEJAQAAAA==.',
Il='Ilbryen:BAAALgAECgUJBQABLgAFFAUJGAADAMogAA==.Illidori:BAABLgAECn8VAAIgAAcJ2ge2iQDjAAAgAAcJ2ge2iQDjAAAAAA==.Illidrag:BAABLgAECn8aAAImAAkJBxJOEwDCAQAmAAkJBxJOEwDCAQAAAA==.Ilovemoo:BAAALgAECgMJAwAAAA==.',
Im='Imblind:BAAALgADCgEJAQABLgAFFAUJEAAKABQWAA==.Imladris:BAAALgAECgYJEAAAAA==.Immortea:BAAALgAECgkJBgAAAA==.Immòrtlzed:BAACLgAFFH8WAAMdAAUJMCJ7CgC/AQAdAAUJMCJ7CgC/AQATAAEJfQfjCwBGAAAuAAQKfyYAAh0ACAnvIG4GAHwCAB0ACAnvIG4GAHwCAAAA.',
In='Invective:BAAALgAECgMJAwAAAA==.',
Is='Isharn:BAAALgADCgMJAwAAAA==.',
Iz='Izzyumi:BAABLgAECn8XAAIhAAcJVgxhXwBKAQAhAAcJVgxhXwBKAQAAAA==.',
Ja='Jabo:BAAALgADCgMJAwABLgAECgcJEgAGAAAAAA==.Jadelin:BAAALgAECgIJAgABLgAECgkJSQAmAOMeAA==.Jaxek:BAABLgAECn84AAIiAAkJ4CJWAQAdAwAiAAkJ4CJWAQAdAwAAAA==.Jaxs:BAACLgAFFH8SAAIZAAcJgBnqAwA7AgAZAAcJgBnqAwA7AgAuAAQKfyAAAhkACAlAG5kVAGgCABkACAlAG5kVAGgCAAAA.Jaylen:BAACLgAFFH8FAAIRAAMJ7hO3HAD6AAARAAMJ7hO3HAD6AAAuAAQKfxQAAhEABglqIQ0YALEBABEABglqIQ0YALEBAAAA.Jaymo:BAABLgAECn8UAAIMAAgJ3xtYCgAnAgAMAAgJ3xtYCgAnAgAAAA==.',
Je='Jebke:BAAALgAECgMJBgABLgAECgYJBwAGAAAAAA==.Jeffurry:BAAALgADCgIJAgAAAA==.Jeminia:BAAALgAECgUJCgAAAA==.Jenifur:BAABLgAECn8VAAILAAYJrQv7aQDVAAALAAYJrQv7aQDVAAAAAA==.Jennae:BAAALgADCgEJAQAAAA==.',
Jh='Jhope:BAABLgAFFH8IAAIQAAMJkA3VMADEAAAQAAMJkA3VMADEAAAAAA==.',
Ji='Jinkusu:BAAALgADCgMJAwABLgAECgkJHAAQACMdAA==.',
Jm='Jml:BAACLgAFFH8UAAIgAAUJDyQ7CQCWAQAgAAUJDyQ7CQCWAQAuAAQKfx4AAiAACQnSIQAFAHYDACAACQnSIQAFAHYDAAAA.',
Jo='Jopha:BAACLgAFFH8VAAMDAAYJSh41BwB5AQADAAUJfiE1BwB5AQACAAIJhAmbJQB0AAAuAAQKfy8AAwMACAlYJQAGAEcDAAMACAk2JQAGAEcDAAIABwkzIPIEAJQCAAAA.Jophr:BAAALgAECgQJAgABLgAFFAYJFQADAEoeAA==.',
Jp='Jpbruiser:BAACLgAFFH8HAAIIAAIJoB5iXQC2AAAIAAIJoB5iXQC2AAAuAAQKfz4AAggACQn2I8gGACEDAAgACQn2I8gGACEDAAAA.',
Ju='Judged:BAAALgAECgYJEQAAAA==.Juggalette:BAAALgADCgIJAgAAAA==.Jumpn:BAAALgAFFAIJBAABLgAFFAUJGAAcALYbAA==.Jumpndeath:BAACLgAFFH8YAAIcAAUJthtVEAAsAQAcAAUJthtVEAAsAQAuAAQKfy0AAxwACQlNIjYGAJwCABwACAnaIjYGAJwCABsACAl9HFE4APwBAAAA.Jumpnpunch:BAABLgAECn8lAAQQAAgJaxwBGgA0AgAQAAcJQBwBGgA0AgAKAAgJ7A90JQBdAQAJAAcJogwHOAALAQABLgAFFAUJGAAcALYbAA==.Junknugget:BAAALgADCgYJBgAAAA==.Justgetme:BAABLgAECn82AAMkAAkJBCZ7AABhAwAkAAkJBCZ7AABhAwAIAAIJAA6lGwFjAAABLgAFFAIJAgAGAAAAAA==.',
Jw='Jwad:BAABLgAECn8lAAMPAAYJBRkvXwBsAQAPAAUJBRkvXwBsAQAXAAIJ8QwEUwB1AAAAAA==.',
Ka='Kaan:BAAALgAECgEJBAAAAA==.Kaariel:BAAALgADCgcJCgAAAA==.Kabo:BAAALgADCgUJCQABLgAFFAUJFQAbADIjAA==.Kagger:BAACLgAFFH8PAAIIAAQJ9B2UHABhAQAIAAQJ9B2UHABhAQAuAAQKfz0AAggACQkuI+8EAH0DAAgACQkuI+8EAH0DAAAA.Kaiser:BAAALgADCgcJDAAAAA==.Kaitu:BAAALgAECgYJCwABLgAECgcJCQAGAAAAAA==.Kake:BAAALgAECgQJBAABLgAFFAMJAwAGAAAAAA==.Kalloh:BAABLgAECn8rAAMPAAcJMRRaZABfAQAPAAcJMRRaZABfAQAXAAIJ4RXEIQB3AAAAAA==.Kalorth:BAAALgADCgcJBwAAAA==.Karazal:BAAALgADCgIJAgAAAA==.Kardoroth:BAACLgAFFH8RAAIbAAUJwCVhGQCrAQAbAAUJwCVhGQCrAQAuAAQKfzcAAhsACQm/JiQDAFwDABsACQm/JiQDAFwDAAAA.Karibo:BAAALgADCgcJDAAAAA==.Karnaege:BAAALgADCgMJAwAAAA==.Karîba:BAACLgAFFH8ZAAQbAAYJ4xrBHwCTAQAbAAUJgBrBHwCTAQAcAAMJPxO/DgB+AAAjAAEJMgsrGgBAAAAuAAQKfy0AAxsACAnTH1IfAMUCABsACAnTH1IfAMUCABwAAQkrCTVNABwAAAAA.Kassi:BAAALgADCgEJAQAAAA==.Kayfree:BAAALgAECgUJCgAAAA==.Kaõtik:BAAALgAECgkJCgAAAA==.',
Kc='Kca:BAAALgAECgEJAQAAAA==.',
Ke='Keerrilee:BAABLgAECn8XAAIKAAkJ7xrEIgBwAQAKAAkJ7xrEIgBwAQAAAA==.Kefka:BAAALgAECgQJBQAAAA==.Keirine:BAAALgAECgEJAwAAAA==.Kelfrost:BAAALgAECgIJAgAAAA==.Kelknight:BAABLgAECn8aAAMcAAQJ0h6bJQD3AAAbAAQJsxpVuwAMAQAcAAMJpR+bJQD3AAAAAA==.Kelsaz:BAACLgAFFH8YAAMNAAYJRhqrAwCmAQANAAYJRxmrAwCmAQAhAAMJchV5CwAGAQAuAAQKfyAABCEACAkqIzISAKYCACEABwlIIzISAKYCACcABglBGPdGADgBAA0ABQlrF0AuABEBAAAA.Kelsi:BAABLgAECn8VAAIKAAkJLxixHQCXAQAKAAkJLxixHQCXAQAAAA==.Kenný:BAAALgAECgEJAQAAAA==.Kerrìgàn:BAACLgAFFH8bAAIeAAYJaBd3AQB5AQAeAAYJaBd3AQB5AQAuAAQKfzAAAx4ACQlcIWkCANYCAB4ACQlcIWkCANYCACYAAQlKDZtZAC8AAAAA.Kestral:BAACLgAFFH8MAAMSAAUJWwEoNgC7AAASAAUJWwEoNgC7AAAdAAMJ6QjIGwCqAAAuAAQKfyYAAx0ACAkMFCoUAAMCAB0ACAkMFCoUAAMCABIAAwn7CnJhAIUAAAAA.Keynis:BAAALgADCgEJAQAAAA==.',
Kh='Khalisi:BAAALgAECgYJCgAAAA==.Khejan:BAAALgADCgMJAwAAAA==.Khrask:BAAALgADCgIJAgABLgAFFAUJGAADAMogAA==.',
Ki='Kiell:BAAALgAECgYJBwAAAA==.Kinuyo:BAAALgAECgQJBAAAAA==.Kirali:BAAALgAECgYJBgAAAA==.Kiwipie:BAAALgAECgQJBAAAAA==.',
Kn='Knottyjack:BAAALgADCgMJAwAAAA==.',
Ko='Kookiie:BAACLgAFFH8WAAMmAAYJ8SAmAgDDAQAmAAYJ8SAmAgDDAQAgAAIJWQ19KwCYAAAuAAQKfyUAAyYACAkTIb4JAMYCACYABwnbJb4JAMYCACAACAkuHL0kAHYCAAAA.Kookiiez:BAAALgAECgQJBAAAAA==.Koom:BAAALgADCgYJBQAAAA==.Kosi:BAAALgAECgQJBQABLgAFFAUJDQASAIUVAA==.Kosian:BAABLgAECn8cAAIkAAgJPQ9WFQBNAQAkAAgJPQ9WFQBNAQAAAA==.Kosigan:BAAALgAECgIJAgABLgAFFAUJDQASAIUVAA==.',
Kp='Kpop:BAAALgADCgEJAQABLgAECgEJAQAGAAAAAA==.',
Kr='Krepuscular:BAAALgAECgMJBAAAAA==.Kroghar:BAAALgADCgYJBgAAAA==.Kromdor:BAABLgAECn8YAAIXAAgJSxoKBgBxAgAXAAgJSxoKBgBxAgAAAA==.Krosis:BAABLgAECn8bAAIbAAkJ6BzwOABTAgAbAAkJ6BzwOABTAgAAAA==.Krumee:BAAALgADCgYJBgAAAA==.',
Kt='Kthríss:BAAALgADCgMJAwAAAA==.',
Ku='Kungscott:BAAALgAECgEJAwABLgAFFAUJBwAIAGkNAA==.Kuromi:BAAALgAECgYJCQAAAA==.',
Ky='Kynei:BAABLgAECn8WAAIgAAgJsx5jIgAqAgAgAAgJsx5jIgAqAgAAAA==.',
La='Lacasis:BAAALgADCgUJBQABLgAECgcJCQAGAAAAAA==.Larra:BAACLgAFFH8YAAQOAAUJoBYrEgCZAQAOAAUJVhYrEgCZAQAlAAMJmgv8CADYAAAYAAIJ3QqDJQCNAAAuAAQKfyEABCUACQnsGioPAG8CACUACAlrHSoPAG8CABgABgnvGzMtAHUBAA4ABgkRDqsrAEoBAAAA.',
Le='Leman:BAAALgADCgkJFAAAAA==.Lemoncrisp:BAAALgAECgEJAQAAAA==.Leprocylarry:BAAALgADCgcJBwAAAA==.Letos:BAAALgAECgcJEgAAAA==.Levelmoo:BAAALgAECgYJBwAAAA==.Levitas:BAABLgAECn8vAAIMAAkJKxOgDgDVAQAMAAkJKxOgDgDVAQAAAA==.Lewieballz:BAAALgADCgMJAwABLgAECgkJIwAGAAAAAA==.',
Li='Liberater:BAAALgAECgEJAQAAAA==.Liljit:BAAALgAECgcJDgAAAA==.Lithel:BAAALgAECgcJCAAAAA==.',
Lo='Loaded:BAAALgAECgEJAQAAAA==.Lockxeno:BAABLgAECn8dAAMPAAgJOBnXMwDxAQAPAAcJOBnXMwDxAQAXAAEJAABGRgAAAAAAAA==.Lodidodii:BAABLgAECn8XAAIVAAgJ7AlzEgBOAQAVAAgJ7AlzEgBOAQAAAA==.Logics:BAACLgAFFH8IAAIYAAQJoBnRDwBJAQAYAAQJoBnRDwBJAQAuAAQKfysAAhgACQkqI/wEAO4CABgACQkqI/wEAO4CAAAA.Lon:BAABLgAECn8YAAIKAAgJxxJlLAB9AQAKAAgJxxJlLAB9AQAAAA==.Longsham:BAAALgADCgEJAQAAAA==.Lostea:BAAALgADCgUJBQABLgAECggJIwASAJ4XAA==.Lostmylimbs:BAACLgAFFH8LAAIcAAQJJQndCgDQAAAcAAQJJQndCgDQAAAuAAQKfysAAhwACAmbGRAQANkBABwACAmbGRAQANkBAAEuAAUUBgkbAB4AaBcA.Lostmyvigor:BAABLgAFFH8FAAIdAAQJKxJrFAAUAQAdAAQJKxJrFAAUAQAAAA==.Lostvoker:BAABLgAECn8jAAMSAAgJnhe8FQAsAgASAAgJnhe8FQAsAgATAAUJehDrIgATAQAAAA==.Loueballz:BAAALgAECgkJIwAAAQ==.Lowvice:BAAALgADCgEJAQAAAA==.',
Lu='Lucarad:BAABLgAECn8yAAIKAAkJXhhjDwAsAgAKAAkJXhhjDwAsAgAAAA==.Lucerfer:BAAALgADCgUJBwAAAA==.Lucivia:BAABLgAECn8xAAIWAAkJTRqfBAAbAgAWAAkJTRqfBAAbAgAAAA==.Lumafist:BAACLgAFFH8JAAIKAAMJ+RzbEgAFAQAKAAMJ+RzbEgAFAQAuAAQKfy8AAgoACQnQIREHALcCAAoACQnQIREHALcCAAAA.Lunirae:BAAALgADCggJDgAAAA==.Luxarion:BAAALgAECgcJBAAAAA==.',
['Lè']='Lènneth:BAACLgAFFH8FAAIlAAMJwBYmFgDhAAAlAAMJwBYmFgDhAAAuAAQKfy0AAyUACQmCHWkJAK4CACUACQmCHWkJAK4CABgAAgnMEH5ZAHEAAAAA.',
['Lí']='Líghtning:BAAALgAECggJDgAAAA==.',
['Lø']='Løstdruid:BAAALgADCgEJAQABLgAECgUJCQAGAAAAAA==.Løstpala:BAAALgAECgUJCQAAAA==.',
Ma='Magewreck:BAAALgADCgcJBwAAAA==.Mahiru:BAAALgADCgMJAwAAAA==.Majimojo:BAAALgAECgIJAwAAAA==.Makkaflocka:BAAALgAECgUJBQABLgAECggJJwAgAOMjAA==.Malleus:BAAALgADCgUJBQAAAA==.Malytheris:BAABLgAECn8iAAMkAAgJJRmBCQAIAgAkAAgJJRmBCQAIAgAIAAEJzgVFdAEqAAAAAA==.Marqis:BAAALgAECgEJAQAAAA==.Mattshanu:BAACLgAFFH8OAAIaAAQJFxhDGQAeAQAaAAQJFxhDGQAeAQAuAAQKfyIAAxoACQkuHrsUAHgCABoACQkuHrsUAHgCABkABAlQGktSADQBAAAA.Mayalaran:BAAALgADCgcJDwAAAA==.Mazgruug:BAAALgAECgcJCgAAAA==.Mazkova:BAAALgAECggJEQAAAA==.Mazur:BAABLgAECn8hAAIIAAgJdSHAIABlAgAIAAgJdSHAIABlAgAAAA==.',
Mc='Mcmonkton:BAAALgAECgcJDAAAAA==.',
Me='Meirah:BAAALgADCgYJBAAAAA==.Mekkaweepz:BAAALgADCgUJBQAAAA==.Melaan:BAABLgAECn8cAAILAAcJtRvVHwAkAgALAAcJtRvVHwAkAgAAAA==.Melinadra:BAAALgAECgEJAQAAAA==.Meowmixx:BAAALgADCgYJBgAAAA==.Meowssa:BAECLgAFFH8QAAIoAAQJDSAqBAB/AQAoAAQJDSAqBAB/AQAuAAQKfy0AAygACQkFJesAAEsDACgACQkFJesAAEsDACIAAglXEU4tAGwAAAAA.Metalplipes:BAAALgADCgQJCgAAAA==.',
Mi='Midori:BAAALgAECgEJAQAAAA==.Mindleseye:BAAALgADCgQJBgAAAA==.Mindlesscon:BAABLgAECn8WAAMVAAYJ0x7YDAD1AQAVAAYJph3YDAD1AQAaAAUJXB6QPABaAQAAAA==.Minislayer:BAAALgAECgcJEQAAAA==.Minyprayers:BAACLgAFFH8bAAMYAAYJ6BVFDQBeAQAYAAUJaBpFDQBeAQAlAAEJvAp0JwBOAAAuAAQKfykAAhgACQkQJc8BAEoDABgACQkQJc8BAEoDAAAA.Minywon:BAAALgADCgcJCgABLgAFFAYJGwAYAOgVAA==.Misosalty:BAACLgAFFH8IAAMKAAMJlRkGFwDlAAAKAAMJUhcGFwDlAAAQAAIJ1BKPOgCOAAAuAAQKfzQAAwoACQnoHwEGAM0CAAoACQnoHwEGAM0CABAABQnXF7hBANYAAAAA.Misowet:BAAALgADCgYJCQABLgAFFAMJCAAKAJUZAA==.',
Ml='Mlorpglorp:BAABLgAECn8hAAIEAAgJuB97PQCCAgAEAAgJuB97PQCCAgAAAA==.',
Mo='Mobaye:BAAALgAECgEJAQAAAA==.Mohjito:BAABLgAECn86AAMKAAkJ7huWCwBkAgAKAAkJ7huWCwBkAgAQAAUJHhGwRQDIAAAAAA==.Mojojojoz:BAAALgADCgUJBQAAAA==.Monkisbad:BAABLgAECn8uAAIQAAgJuyNiDADJAgAQAAgJuyNiDADJAgAAAA==.Monkma:BAAALgAECgIJAgAAAA==.Moonfire:BAAALgADCgcJDgAAAA==.Moose:BAAALgADCgYJBgAAAA==.Mooshanu:BAAALgADCgcJDAABLgAFFAQJDgAaABcYAA==.Morguth:BAACLgAFFH8SAAMhAAUJZBfsJAA7AQAhAAUJZBfsJAA7AQAnAAIJUQCtIwBdAAAuAAQKfx0ABCEACQl7HSUUAJUCACEACQl7HSUUAJUCACcABAkeBLVnAKAAAA0AAgliD4RVADcAAAAA.Moriaug:BAAALgAFFAIJAgABLgAFFAQJBwAEACkeAA==.Moriko:BAABLgAECn8VAAMOAAgJsAu0KwA9AQAOAAcJTQy0KwA9AQAYAAEJ/QTsdAAtAAAAAA==.',
Mu='Muggy:BAAALgAECgEJBAAAAA==.Murky:BAACLgAFFH8FAAIRAAIJrxOkJQChAAARAAIJrxOkJQChAAAuAAQKfy0AAhEACAlcH2MJAGwCABEACAlcH2MJAGwCAAAA.Musicmichael:BAAALgAECgYJCQAAAA==.',
['Mî']='Mîyagî:BAAALgAECgcJCQAAAA==.',
['Mö']='Mööbs:BAABLgAECn84AAMdAAkJKQeJFABfAQAdAAkJKQeJFABfAQASAAYJfQYeSwCnAAAAAA==.',
Na='Namad:BAAALgAECgYJDwAAAA==.Nancybrew:BAABLgAECn8mAAMKAAkJoR8mCgB8AgAKAAkJoR8mCgB8AgAJAAIJdRJ3WABtAAAAAA==.Natalie:BAAALgAECgEJAgABLgAECgEJAgAGAAAAAA==.Nathric:BAAALgADCgUJBQAAAA==.Navajo:BAAALgAECgcJEwAAAA==.',
Ne='Neature:BAAALgADCgMJAwAAAA==.Neoma:BAABLgAECn8eAAIPAAYJGQx2kQADAQAPAAYJGQx2kQADAQAAAA==.Nesqwik:BAAALgAECgQJCAAAAA==.Nevan:BAABLgAECn8pAAMHAAkJByTIBgD+AgAHAAkJByTIBgD+AgAIAAQJKBHetQD0AAAAAA==.Neverender:BAAALgAECgEJAgABLgAECgYJEAAGAAAAAA==.Newlock:BAAALgAECgQJBAAAAA==.Nexi:BAAALgAECgMJAwAAAA==.',
Ni='Niang:BAAALgADCgQJBAAAAA==.Nidalee:BAAALgAECggJEQAAAA==.Nippyvixen:BAAALgAECgEJAQAAAA==.Nishu:BAAALgADCgMJAwAAAA==.',
No='Noochallange:BAABLgAECn8zAAIfAAkJHyEnAQDrAgAfAAkJHyEnAQDrAgAAAA==.Norex:BAACLgAFFH8SAAQbAAUJmRcCQQBDAQAbAAQJmRcCQQBDAQAjAAEJVApTGABIAAAcAAEJAAB+QwAAAAAuAAQKfyEAAxsACQkmE9VaAOEBABsACQmzEtVaAOEBABwABgmfCLosANkAAAAA.Norm:BAAALgAECgYJCwAAAA==.Notekk:BAAALgAECgQJBwAAAA==.Nottygerbil:BAAALgAECgMJAwAAAA==.',
Nu='Nuggie:BAABLgAECn8gAAMPAAkJ5BmpJgAoAgAPAAgJ5BmpJgAoAgAXAAEJAADGYgBJAAAAAA==.Nurf:BAAALgADCgMJAwAAAA==.Nurgal:BAAALgAECgYJCAAAAA==.Nutlips:BAAALgADCgUJCwABLgAECgMJBgAGAAAAAA==.',
Ny='Nylariaa:BAAALgAECgYJEgAAAA==.Nymia:BAABLgAECn8nAAMLAAkJMRzuGgBKAgALAAkJMRzuGgBKAgABAAEJthiSawBIAAAAAA==.',
['Næ']='Næon:BAABLgAECn8gAAIJAAkJcxhZFQAzAgAJAAkJcxhZFQAzAgAAAA==.',
Ob='Oblake:BAABLgAECn8YAAIRAAcJkBQmIQDwAQARAAcJkBQmIQDwAQAAAA==.',
Oc='Octosloth:BAAALgADCgEJAQAAAA==.',
Oh='Ohhashbrowns:BAAALgADCgcJBwAAAA==.',
Ok='Oku:BAAALgADCgcJBgAAAA==.',
Ol='Oldmagic:BAAALgAECgYJEwAAAA==.Olizza:BAAALgAECgIJAgABLgAECgcJIgAhAIIQAA==.',
Om='Omgimabeast:BAAALgAECgYJCAAAAA==.',
On='Onieva:BAAALgAECgkJDgAAAA==.',
Oo='Ooglaboogla:BAABLgAECn84AAMaAAkJWCDCBgDSAgAaAAkJWCDCBgDSAgAZAAIJhxyRggCJAAAAAA==.',
Or='Oriah:BAAALgADCgYJBgAAAA==.Orions:BAAALgADCgQJBAAAAA==.Orygor:BAAALgADCgIJAgAAAA==.',
Os='Osserc:BAAALgAECgQJBAAAAA==.',
Ox='Oxyrotten:BAABLgAECn8bAAIbAAYJ9gxErADxAAAbAAYJ9gxErADxAAAAAA==.',
Pa='Pablo:BAABLgAECn82AAMNAAkJmSG+BQCxAgANAAkJmSG+BQCxAgAnAAEJZREShwA1AAAAAA==.Pancho:BAABLgAECn8bAAIKAAkJehdeEAAhAgAKAAkJehdeEAAhAgAAAA==.Pandra:BAAALgADCgEJAQAAAA==.Panttyraider:BAAALgAFFAIJAgAAAA==.Panzeria:BAABLgAECn8dAAIYAAcJPSU8CQDwAgAYAAcJPSU8CQDwAgAAAA==.Papito:BAAALgAFFAIJAgAAAA==.Pathryis:BAAALgAECgYJBgAAAA==.Pawsome:BAAALgADCgIJAgAAAA==.',
Pl='Plank:BAAALgAECgUJBwAAAA==.',
Pm='Pmon:BAAALgADCgEJAQAAAA==.',
Po='Pongo:BAAALgAECgcJDwAAAA==.Ponkofox:BAACLgAFFH8HAAIVAAMJgAqZCQDSAAAVAAMJgAqZCQDSAAAuAAQKfx8AAhUACAlAFAkOANwBABUACAlAFAkOANwBAAAA.',
Pr='Prah:BAAALgAECgcJDAAAAA==.Prepared:BAAALgAECgIJAgAAAA==.Prise:BAAALgAECgMJBgAAAA==.Prisefather:BAAALgAECgYJCgAAAA==.Prisefightr:BAAALgAECgEJAQAAAA==.Prizefighter:BAAALgAECgYJDQAAAA==.Proditus:BAAALgAECgMJAwAAAA==.Proowee:BAAALgAECggJCAAAAA==.',
Ps='Pseudoholy:BAAALgADCgEJAQAAAA==.',
Pu='Putridvigor:BAACLgAFFH8GAAIcAAMJYxsLFwDxAAAcAAMJYxsLFwDxAAAuAAQKfyAAAxwACQnbGAkKAEUCABwACQnbGAkKAEUCABsAAwmfBlz9AHIAAAAA.Puzzlewalrus:BAAALgADCgQJBAAAAA==.',
Py='Pyreiella:BAAALgADCgUJBQAAAA==.Pyroamor:BAAALgAECgEJAQAAAA==.Pyropete:BAABLgAFFH8FAAIEAAIJ3gEakwB2AAAEAAIJ3gEakwB2AAAAAA==.',
['Pä']='Pälii:BAABLgAECn8nAAMHAAkJdQfqLwByAQAHAAkJdQfqLwByAQAIAAQJhA4l4QDLAAAAAA==.',
Qc='Qcomberoo:BAAALgADCgMJAwAAAA==.',
Ra='Ragublaster:BAAALgAECgEJAQABLgAFFAYJEgASAIYYAA==.Ragz:BAAALgAECggJCQAAAA==.Ralickan:BAAALgADCgcJBQAAAA==.Ramaan:BAABLgAECn8hAAIZAAkJ+hu1DADLAgAZAAkJ+hu1DADLAgAAAA==.Ramble:BAAALgAECgcJDQAAAA==.Ravette:BAABLgAECn82AAMmAAkJvyOuAgAQAwAmAAkJvyOuAgAQAwAeAAMJnBNWHgCVAAAAAA==.Ravissante:BAABLgAECn8eAAIgAAcJ2wbqhwDnAAAgAAcJ2wbqhwDnAAAAAA==.Rawranator:BAAALgAECgYJDgAAAA==.',
Re='Reesecupthis:BAABLgAECn8fAAIkAAgJHCJyBQBxAgAkAAgJHCJyBQBxAgABLgAFFAYJFQAkAHcbAA==.Remagix:BAAALgAECgEJAQAAAA==.Remix:BAAALgAECgEJAQAAAA==.Revek:BAAALgADCgEJAQAAAA==.Reveurus:BAAALgADCgcJBwABLgAECgkJKQAHAAckAA==.Rezzaleya:BAAALgADCgQJBAAAAA==.',
Rh='Rhaena:BAAALgAECgYJDQABLgAECgkJDgAGAAAAAA==.Rhonis:BAAALgAECgYJDAAAAA==.',
Ri='Riceroll:BAABLgAECn8bAAMPAAcJKyCJUwCKAQAPAAYJ6x6JUwCKAQAXAAQJIB0zJAA4AQAAAA==.Rickyspanish:BAAALgAECgcJBAAAAA==.Ricochet:BAABLgAECn8wAAIHAAgJ8RUMKgCXAQAHAAgJ8RUMKgCXAQAAAA==.Rioszen:BAAALgADCgIJAgAAAA==.Riseordie:BAAALgADCgYJCAAAAA==.',
Ro='Rollmybitzup:BAAALgAFFAEJAwABLgAFFAYJEgASAIYYAA==.Ronnycoleman:BAAALgAECgMJAwAAAA==.Roofonfire:BAABLgAECn8bAAMVAAgJsglkFgAWAQAVAAgJ7AhkFgAWAQAaAAMJvwYzdwBmAAAAAA==.Roreck:BAAALgAECgkJBAAAAA==.Rowyn:BAAALgADCgEJAQAAAA==.',
Ru='Runeka:BAACLgAFFH8GAAIOAAMJqyEbHAApAQAOAAMJqyEbHAApAQAuAAQKfyMAAg4ACAmZJXEHAMsCAA4ACAmZJXEHAMsCAAAA.Rusalkha:BAAALgADCgEJAQAAAA==.Ruteefear:BAABLgAECn8UAAMPAAcJVxzjOwDSAQAPAAcJUhzjOwDSAQAWAAMJUxvfEwDyAAAAAA==.',
Ry='Rybes:BAAALgAECgcJEgAAAA==.Rychesus:BAAALgADCgYJBgABLgAECgUJCQAGAAAAAA==.',
Sa='Safehaven:BAAALgAECgMJAwAAAA==.Saintcloud:BAAALgADCgkJEAAAAA==.Sairuwki:BAAALgAECgkJCQAAAA==.Samwìse:BAACLgAFFH8YAAIlAAUJ4Q72CwBTAQAlAAUJ4Q72CwBTAQAuAAQKfzQAAyUACAkzJHUOAHYCACUACAkzJHUOAHYCABgABwlKFA8kAIABAAAA.Sandrokos:BAAALgADCgUJCgAAAA==.Sareir:BAAALgADCgMJAwAAAA==.Sarranidan:BAAALgADCgMJAwABLgAECggJHAAkAD0PAA==.Sato:BAAALgAECgEJAQAAAA==.Savagex:BAAALgADCgYJBgAAAA==.Saveena:BAAALgAECgYJEgAAAA==.',
Sc='Scarlla:BAABLgAECn8XAAIZAAkJlR7NDADJAgAZAAkJlR7NDADJAgAAAA==.Scorber:BAAALgAECgIJAgAAAA==.',
Se='Searingbear:BAAALgAECgQJBQABLgAECggJGgAKAEYXAA==.Senggolbacok:BAAALgAFFAIJAgAAAA==.Senpaii:BAAALgAECgEJAwAAAA==.Senseitheta:BAAALgAECgEJAgABLgAECggJHQAPADgZAA==.Sepherios:BAAALgADCgYJBgAAAA==.Serengenuity:BAAALgAFFAEJAQAAAA==.Serenidin:BAAALgAECgEJAQAAAA==.Serenio:BAAALgAECgEJBAAAAA==.Sereniswift:BAAALgAECgQJBQAAAA==.Serephita:BAABLgAECn8uAAIEAAkJnAi1bQCCAQAEAAkJnAi1bQCCAQAAAA==.',
Sg='Sgtsnipe:BAAALgAECgQJBQAAAA==.',
Sh='Shakys:BAABLgAECn8fAAMEAAgJ4BgtSADnAQAEAAgJ4BgtSADnAQApAAEJqwjEDwAvAAAAAA==.Shalaylea:BAAALgAECgUJCAAAAA==.Shamruce:BAAALgADCgYJBgAAAA==.Shamwich:BAABLgAECn8fAAMaAAcJ5RCrMQBIAQAaAAcJ5RCrMQBIAQAZAAQJtARNigCAAAAAAA==.Shanondorf:BAABLgAECn8bAAMUAAgJ3xuCBAAOAgAUAAgJ5hqCBAAOAgARAAUJdxogLgD7AAAAAA==.Shark:BAABLgAECn8YAAMLAAYJ7RIcRQBYAQALAAYJ7RIcRQBYAQABAAUJ/QvrPwDcAAABLgAFFAYJGAAbAFEUAA==.Shaymist:BAAALgAECgMJAwAAAA==.Sheeplord:BAAALgADCgQJBgAAAA==.Sheepstealer:BAABLgAECn82AAMSAAkJ6BPlGQDnAQASAAkJ6BPlGQDnAQATAAQJLgJJNAByAAAAAA==.Shiggyll:BAAALgADCgIJAgAAAA==.Shildo:BAABLgAECn8tAAMYAAkJhhrbDgBGAgAYAAkJhhrbDgBGAgAOAAEJQQutVAA4AAAAAA==.Shirokuma:BAAALgAECgMJAwAAAA==.Shiryunuri:BAAALgADCgUJCAAAAA==.Shizzo:BAAALgAECgYJEgAAAA==.Shockrock:BAAALgAECgQJBQAAAA==.Shybuzz:BAAALgAECggJCgAAAA==.Shøstákovich:BAAALgADCgEJAQAAAA==.',
Si='Sifen:BAABLgAFFH8HAAIIAAUJaQ0ZNQAkAQAIAAUJaQ0ZNQAkAQAAAA==.Silecra:BAAALgADCgcJBwABLgAFFAMJBgAOAKshAA==.Sinscale:BAAALgAECgQJBAABLgAFFAYJFgAIAFYdAA==.Sinswrath:BAACLgAFFH8WAAIIAAYJVh1NDgCkAQAIAAYJVh1NDgCkAQAuAAQKfyUAAggACAkWJIQJAEUDAAgACAkWJIQJAEUDAAAA.',
Sk='Skarre:BAACLgAFFH8DAAIgAAIJyAmTZwCFAAAgAAIJyAmTZwCFAAAuAAQKfyEAAiAABwnbHDAwADoCACAABwnbHDAwADoCAAAA.Skcusnor:BAABLgAECn8WAAIhAAkJfwzxTACOAQAhAAkJfwzxTACOAQAAAA==.Skelevyrn:BAAALgADCgEJAQAAAA==.Skimnms:BAAALgADCgUJBgAAAA==.Skrimbly:BAAALgAECgEJAQAAAA==.',
Sl='Slaye:BAAALgAECgkJEwAAAA==.',
Sm='Smiteheal:BAAALgADCgMJAwAAAA==.Smores:BAACLgAFFH8TAAILAAUJ3iDiCgDwAQALAAUJ3iDiCgDwAQAuAAQKfyAAAgsACQkAJaYEAEQDAAsACQkAJaYEAEQDAAEuAAUUCAkmAAsAIhwA.Smrts:BAAALgAECggJCwAAAA==.',
Sn='Snaccident:BAACLgAFFH8JAAMTAAMJdgibBgCuAAATAAMJiAKbBgCuAAASAAMJIQg8QgB/AAAuAAQKfycAAxIACQnFEQAhALgBABIACQnFEQAhALgBABMAAQnBAHJGABkAAAAA.Snaccidentsh:BAAALgADCgMJAgABLgAFFAMJCQATAHYIAA==.Snaccidentww:BAABLgAECn8UAAIKAAgJEQpyLwAhAQAKAAgJEQpyLwAhAQABLgAFFAMJCQATAHYIAA==.Sneakyteeth:BAABLgAECn8oAAIRAAkJFxPCDwAOAgARAAkJFxPCDwAOAgAAAA==.Snotzz:BAAALgAECgcJDQAAAA==.',
So='Sojukai:BAAALgAECgEJAQAAAA==.Sok:BAAALgAECgUJDgAAAA==.Solonör:BAAALgADCgcJCAAAAA==.Songi:BAABLgAECn8fAAIbAAgJFiJ4KACZAgAbAAgJFiJ4KACZAgAAAA==.Soulwhisper:BAACLgAFFH8WAAIbAAYJSRmxIwCGAQAbAAYJSRmxIwCGAQAuAAQKfyYAAhsACAm1JFIVAPwCABsACAm1JFIVAPwCAAAA.',
Sp='Spaghetifire:BAABLgAFFH8SAAISAAYJhhjgDwCUAQASAAYJhhjgDwCUAQAAAA==.Sparklybeach:BAAALgADCggJCAAAAA==.Sphyr:BAABLgAECn8eAAMIAAkJuAYwfwBQAQAIAAkJKAYwfwBQAQAkAAQJVQW4MgBqAAAAAA==.Spicynoodi:BAABLgAECn8cAAMTAAgJhgfWHQA/AQATAAcJgwfWHQA/AQASAAMJ0gVLZQB2AAAAAA==.Spyrodruid:BAAALgAFFAEJAQABLgAFFAUJEwAcAMQeAA==.Spyromonk:BAABLgAFFH8FAAIQAAQJwBDgHwAQAQAQAAQJwBDgHwAQAQABLgAFFAUJEwAcAMQeAA==.',
Sq='Sqoots:BAABLgAECn8hAAIEAAgJDiJ4IQDtAgAEAAgJDiJ4IQDtAgAAAA==.',
St='Stankyfist:BAAALgAECgUJCAAAAA==.Starfeish:BAAALgAECgcJEAAAAA==.Stepzlol:BAAALgADCgIJAwAAAA==.Stopresistin:BAAALgAECgUJCQAAAA==.Stormsinger:BAABLgAECn8pAAMaAAkJPxctGQDsAQAaAAkJPxctGQDsAQAZAAgJDBGBTgBJAQAAAA==.Stårrßerry:BAAALgAECgIJAgAAAA==.',
Su='Succubis:BAAALgADCgIJAgAAAA==.Sugarblast:BAACLgAFFH8NAAMaAAUJIhyTCQBEAQAaAAQJIhyTCQBEAQAVAAEJAABCEgAAAAAuAAQKfyMAAhoACAn7IwwLAOcCABoACAn7IwwLAOcCAAAA.Sukker:BAAALgAECgMJBgAAAA==.Sukkler:BAAALgADCgYJCAAAAA==.Sumtingwong:BAAALgADCgYJBgAAAA==.Suou:BAACLgAFFH8YAAMDAAUJyiC4DABpAQADAAUJyiC4DABpAQACAAEJlQmbCwBUAAAuAAQKfyUAAwMACQkMIdUbAOoBAAMABwk6IdUbAOoBAAIAAgmBIKw5AKsAAAAA.Supadoc:BAACLgAFFH8JAAIZAAMJ7x7qJQATAQAZAAMJ7x7qJQATAQAuAAQKfxYAAhkACQl3DmAzALUBABkACQl3DmAzALUBAAAA.Superchicken:BAAALgAECgIJAgAAAA==.Surfbird:BAAALgAECgYJBgAAAA==.',
Sv='Svekkê:BAAALgAECgcJBwAAAA==.',
Sw='Swagmeoutbro:BAAALgADCgIJAgAAAA==.',
Sy='Sylint:BAAALgAECgYJCQAAAA==.Sylliseas:BAAALgADCgYJBgAAAA==.Sylvara:BAAALgAECgUJBwAAAA==.Sylverhooves:BAAALgAECgUJCwAAAA==.Sylverlock:BAAALgAECgIJAgAAAA==.',
Ta='Ta:BAAALgADCgIJAgAAAA==.Tacosdk:BAAALgAECgUJCAAAAA==.Tacoss:BAAALgAECgIJAgAAAA==.Taladiira:BAAALgADCgcJAgAAAA==.Tandea:BAAALgAECgEJAQAAAA==.Tandragosa:BAAALgAECgMJBAABLgAECgkJKQAaAD8XAA==.Tankadiin:BAAALgAECgQJBAAAAA==.Tannica:BAAALgADCgYJBgAAAA==.Tanthyr:BAAALgAECgYJCAAAAA==.Tayswiftagos:BAAALgAECgcJEAABLgAECgcJGAAeADYeAA==.',
Te='Teddy:BAAALgADCgMJAwAAAA==.Teddyy:BAAALgAECgcJBwAAAA==.Testme:BAAALgADCgYJBgAAAA==.Texazmade:BAAALgAECgUJBgAAAA==.Textacô:BAAALgAECgUJBQABLgAECgUJBgAGAAAAAA==.',
Th='Thagomizer:BAAALgADCgIJAgAAAA==.Thechadlad:BAAALgADCgYJBgAAAA==.Thedevilssin:BAACLgAFFH8FAAIoAAMJZAV/FwCBAAAoAAMJZAV/FwCBAAAuAAQKfxkAAigABwlPFi4UAHgBACgABwlPFi4UAHgBAAAA.Thefool:BAAALgADCgYJBgAAAA==.Theocles:BAAALgADCgYJDwAAAA==.Theodas:BAABLgAECn8VAAIbAAgJfBfDQADfAQAbAAgJfBfDQADfAQAAAA==.Therru:BAAALgADCggJGAABLgAECggJFQAOALALAA==.Thibbledorf:BAAALgAECgQJBAAAAA==.Thien:BAAALgADCgkJCQAAAA==.Thorimm:BAAALgAECgEJAQAAAA==.Throbbert:BAAALgADCgcJBwABLgAECggJGwAUAN8bAA==.Thunderhunt:BAAALgADCgMJAwABLgAECgQJCAAGAAAAAA==.Thunderwater:BAAALgAECgQJCAAAAA==.Thunis:BAAALgAFFAIJAgABLgAFFAUJBwAIAGkNAA==.',
Ti='Tiken:BAAALgAECgEJAwAAAA==.Tiktok:BAABLgAECn8YAAMeAAcJNh6ZCgC7AQAeAAcJNh6ZCgC7AQAgAAIJcQoP+gAmAAAAAA==.Tippss:BAACLgAFFH8SAAIlAAUJ0iDXBADOAQAlAAUJ0iDXBADOAQAuAAQKfzgAAyUACQnDJfgBAFQDACUACQnDJfgBAFQDAA4ACAmrFvQSAB4CAAAA.Tipsygypsy:BAABLgAECn8qAAIEAAgJMwlNiQBJAQAEAAgJMwlNiQBJAQAAAA==.Tique:BAAALgAECgYJBgAAAA==.',
To='Tokenbeef:BAACLgAFFH8KAAIZAAMJxBMDNwDQAAAZAAMJxBMDNwDQAAAuAAQKfzUAAxkACQmUG9IOALMCABkACQmUG9IOALMCABoAAwlEBBJ2AGoAAAAA.Tokenshaman:BAACLgAFFH8FAAIVAAMJlwfgCQDIAAAVAAMJlwfgCQDIAAAuAAQKfyIAAhUABwn2EOcRAFcBABUABwn2EOcRAFcBAAAA.Torlon:BAAALgADCgEJAQAAAA==.Toxicdk:BAABLgAFFH8KAAMbAAUJmQ74UAArAQAbAAQJmQ74UAArAQAcAAIJ9QriLwAyAAAAAA==.Toxicshamy:BAACLgAFFH8GAAMVAAIJXw83DACWAAAVAAIJAA83DACWAAAaAAIJKgSbGQCIAAAuAAQKfyYABBUACQmrHAMEAJICABUACAnXHwMEAJICABoABwnQEycpAMsBABkAAQm1GBKmAEQAAAEuAAUUBQkKABsAmQ4A.',
Tr='Trafficcones:BAAALgAECgMJAwAAAA==.Traugdor:BAAALgADCgkJDgAAAA==.Traylay:BAACLgAFFH8VAAIIAAUJlxzXIABTAQAIAAUJlxzXIABTAQAuAAQKfyEAAggACQnaJKEMACkDAAgACQnaJKEMACkDAAAA.Traylei:BAAALgADCgcJBwABLgAFFAUJFQAIAJccAA==.Tremana:BAAALgAECgMJAwAAAA==.Trio:BAAALgADCgUJBQAAAA==.Trixaintime:BAABLgAECn8WAAIIAAYJUQlzqwArAQAIAAYJUQlzqwArAQAAAA==.',
Ts='Tsm:BAAALgADCgYJBgAAAA==.',
Tt='Ttocs:BAACLgAFFH8RAAIaAAQJTRYvGAAlAQAaAAQJTRYvGAAlAQAuAAQKfzIAAhoACQnJI2ICADgDABoACQnJI2ICADgDAAEuAAUUBQkHAAgAaQ0A.',
Tu='Tujori:BAACLgAFFH8LAAMOAAUJiA72DgDgAAAOAAQJMBH2DgDgAAAlAAEJ6APMKABHAAAuAAQKfx4AAyUACAmeEp0uAIkBACUACAlJC50uAIkBAA4ABwm+ErclAGcBAAAA.Turuce:BAAALgADCgYJBgAAAA==.',
Tv='Tv:BAAALgADCgcJBwABLgAECgMJAwAGAAAAAA==.',
Tw='Twherk:BAAALgAFFAEJAQABLgAFFAYJDwAOAPsQAA==.Twinmoonfury:BAACLgAFFH8GAAIBAAQJFwZIIgDjAAABAAQJFwZIIgDjAAAuAAQKfzwAAwEACQn8G/wKAH8CAAEACQn8G/wKAH8CAAsABgk8E7xaAEIBAAAA.Twobit:BAAALgAECggJCQAAAA==.',
Ty='Tylann:BAAALgADCgIJAgAAAA==.Tynestra:BAABLgAECn8kAAIgAAkJKhZbKgABAgAgAAkJKhZbKgABAgAAAA==.',
['Tí']='Tíger:BAAALgADCgQJAwAAAA==.',
['Tü']='Tüyria:BAAALgADCgMJAwAAAA==.',
Ug='Uglydorf:BAABLgAECn8sAAIhAAkJshorGABsAgAhAAkJshorGABsAgAAAA==.',
Uh='Uhh:BAAALgADCgcJCQAAAA==.',
Ul='Ulraka:BAAALgADCgEJAQAAAA==.Ultraviolenc:BAAALgAECgEJAQAAAA==.',
Un='Unholydiver:BAAALgADCgEJAQAAAA==.',
Va='Vaeros:BAABLgAECn8iAAISAAgJ/w+AKAB+AQASAAgJ/w+AKAB+AQAAAA==.Valantis:BAEALgAECgQJBQAAAA==.Valcantor:BAAALgAECgYJDAAAAA==.Vanyss:BAAALgADCgYJBgAAAA==.',
Ve='Vekz:BAABLgAECn8tAAIHAAkJ/B+2DwB4AgAHAAkJ/B+2DwB4AgAAAA==.Velazq:BAAALgADCgEJAgAAAA==.Velicia:BAABLgAECn8iAAICAAgJnxrHDADzAQACAAgJnxrHDADzAQAAAA==.Velithice:BAAALgAECgYJBwAAAA==.Venture:BAAALgAECgQJBAAAAA==.',
Vo='Voidnjoyr:BAAALgAECgEJAQAAAA==.',
Wa='Walsun:BAAALgADCgcJDQABLgAECgkJKQAaAD8XAA==.Warheadx:BAAALgAECgQJBAAAAA==.Warhéad:BAAALgAECgUJDwAAAA==.Wartonxp:BAABLgAECn8sAAIYAAgJfx5ADgCfAgAYAAgJfx5ADgCfAgAAAA==.Waterbôy:BAACLgAFFH8TAAMaAAUJchi+FQAyAQAaAAQJchi+FQAyAQAZAAMJfQvGPAC8AAAuAAQKfzgABBoACQnoIfEIAKwCABoACQnoIfEIAKwCABkABQliCZdnAPAAABUAAgktBQgoAFwAAAAA.Waynee:BAAALgAECgcJDAAAAA==.',
We='Weepylight:BAAALgAECgMJAwAAAA==.Weissbrew:BAAALgADCgUJBQAAAA==.',
Wh='Wheezy:BAAALgAFFAIJAgAAAA==.Whoasked:BAACLgAFFH8NAAISAAUJhRUcHgAlAQASAAUJhRUcHgAlAQAuAAQKfzkAAxIACQmuJS4CAFIDABIACQmuJS4CAFIDABMABglJFyscAE8BAAAA.',
Wi='Wiggle:BAABLgAECn88AAIFAAkJQyJOAAAkAwAFAAkJQyJOAAAkAwAAAA==.Wildslayer:BAAALgADCgUJBQAAAA==.',
Wo='Wolf:BAAALgAECgEJAQAAAA==.',
Wt='Wtfheal:BAACLgAFFH8PAAIOAAYJ+xD/EwCCAQAOAAYJ+xD/EwCCAQAuAAQKfyUAAg4ACAkaI7QFAPMCAA4ACAkaI7QFAPMCAAAA.',
Xa='Xalash:BAAALgADCgEJAQAAAA==.Xanistra:BAACLgAFFH8WAAIPAAUJ6RpmNgA4AQAPAAUJ6RpmNgA4AQAuAAQKfyUAAw8ACQkqH0oNABADAA8ACQkqH0oNABADABcABAm/HFUtAAgBAAAA.Xaylor:BAAALgADCgcJCgAAAA==.',
Xg='Xgamesmode:BAAALgADCgUJBgABLgAFFAMJCQAKAPkcAA==.',
Xz='Xzlemina:BAAALgAECgcJCQAAAA==.',
Ya='Yalaforth:BAABLgAECn8mAAIIAAkJIBNqQwDdAQAIAAkJIBNqQwDdAQAAAA==.Yamashaman:BAABLgAECn86AAMZAAkJcCDXBABCAwAZAAkJcCDXBABCAwAaAAIJxgd/lwAjAAABLgAFFAUJBgAbANYLAA==.Yardgnome:BAABLgAECn8ZAAILAAcJHxSrNAClAQALAAcJHxSrNAClAQAAAA==.',
Ye='Yebefd:BAAALgADCgcJBwAAAA==.',
Yu='Yungbluudd:BAABLgAFFH8GAAIRAAMJqxtUGQAZAQARAAMJqxtUGQAZAQAAAA==.',
Za='Zaleth:BAAALgAECgQJBQAAAA==.Zaliel:BAAALgAECgEJAgAAAA==.Zamasu:BAABLgAECn8nAAIgAAgJ4yN9DQC+AgAgAAgJ4yN9DQC+AgAAAA==.Zapmybitzup:BAABLgAFFH8FAAIVAAMJ9gu2CQDPAAAVAAMJ9gu2CQDPAAABLgAFFAYJEgASAIYYAA==.Zaroneus:BAAALgADCgUJBQAAAA==.Zaszadin:BAECLgAFFH8ZAAIIAAUJ9iU4CwC6AQAIAAUJ9iU4CwC6AQAuAAQKfycAAggACQlfI+sZAM0CAAgACQlfI+sZAM0CAAAA.Zaszhadoom:BAEALgAECgcJCQABLgAFFAUJGQAIAPYlAA==.Zaxxon:BAABLgAECn80AAMSAAkJrCESBAAWAwASAAkJrCESBAAWAwATAAEJDQ3LPgA0AAAAAA==.',
Ze='Zekt:BAAALgADCgQJBAAAAA==.Zelo:BAAALgAECgYJCwAAAA==.Zensi:BAAALgAECgEJAQAAAA==.Zerax:BAABLgAECn8yAAIdAAkJcRqUBwBdAgAdAAkJcRqUBwBdAgAAAA==.',
Zi='Zigfury:BAAALgAECgYJDwAAAA==.Zillagoth:BAAALgAECgMJAgAAAA==.Zira:BAABLgAECn8zAAIJAAkJERNsHgDkAQAJAAkJERNsHgDkAQAAAA==.',
Zo='Zombiebrainz:BAAALgAECgUJCQAAAA==.Zombiebubble:BAAALgAECgkJDwAAAA==.Zoìdberg:BAACLgAFFH8SAAIZAAMJyiGdIQAnAQAZAAMJyiGdIQAnAQAuAAQKfzwAAhkACQmDIbMHAPoCABkACQmDIbMHAPoCAAAA.',
Zs='Zselk:BAAALgADCgYJCAAAAA==.',
Zu='Zubzer:BAABLgAECn8dAAIbAAkJsBkRKgA1AgAbAAkJsBkRKgA1AgAAAA==.',
Zz='Zzor:BAACLgAFFH8fAAIEAAUJ2yB7LQBuAQAEAAUJ2yB7LQBuAQAuAAQKfyUAAgQACQkrJREPAE8DAAQACQkrJREPAE8DAAAA.Zzorfel:BAAALgAECgcJCAABLgAFFAUJHwAEANsgAA==.Zzorshock:BAAALgAECgYJDAABLgAFFAUJHwAEANsgAA==.',
['Ði']='Ðii:BAAALgAECgMJAwAAAA==.',
['ßl']='ßlue:BAACLgAFFH8GAAIEAAMJvQNVcwDHAAAEAAMJvQNVcwDHAAAuAAQKfyUAAgQACQnxEqFEAPIBAAQACQnxEqFEAPIBAAEuAAUUBAkFABAAHxAA.',
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
