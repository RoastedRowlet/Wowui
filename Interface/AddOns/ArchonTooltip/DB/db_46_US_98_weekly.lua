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

local lookup = {'Druid-Balance','Warrior-Arms','Warrior-Fury','Mage-Frost','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Druid-Restoration','Paladin-Protection','Hunter-Survival','Priest-Holy','Warlock-Demonology','Monk-Brewmaster','Rogue-Subtlety','Priest-Discipline','Evoker-Augmentation','Evoker-Devastation','Rogue-Outlaw','Shaman-Enhancement','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Evoker-Preservation','DemonHunter-Vengeance','Rogue-Assassination','DemonHunter-Devourer','Hunter-BeastMastery','Druid-Feral','DeathKnight-Frost','DemonHunter-Havoc','Hunter-Marksmanship','Druid-Guardian','Mage-Fire',}
local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Aberdus:BAABLgAECn8YAAIBAAcJIhV9JABLAQABAAcJIhV9JABLAQAAAA==.',
Ac='Accalon:BAABLgAECn8jAAMCAAgJcxjxDADDAQACAAgJGBjxDADDAQADAAIJixDyXAB/AAABLgAECgcJGwAEAKAZAA==.',
Ad='Adina:BAAALgAECgYJBgAAAA==.Advacus:BAACLgAFFH8UAAMEAAUJahdeNQBNAQAEAAUJYRReNQBNAQAFAAIJ6hVkAgBdAAAuAAQKfyUAAwUACAlmH/8BAJACAAUACAmWGv8BAJACAAQACAkEHEZQAEYCAAAA.',
Ai='Aicila:BAAALgADCgEJAQAAAA==.Aimer:BAAALgAECgEJAQAAAA==.Airi:BAAALgADCgYJCAAAAA==.',
Ak='Akrama:BAABLgAECn8tAAMGAAkJuRzTEABGAgAGAAkJuRzTEABGAgAHAAYJdAk6qgDaAAAAAA==.',
Al='Alara:BAAALgADCgkJEwAAAA==.Alatáriel:BAAALgAECgIJAgAAAA==.Alectrona:BAAALgAECgQJBQAAAA==.Aletriss:BAAALgAECgQJCgAAAA==.Alexsham:BAAALgAECgEJAQAAAA==.Algaraz:BAAALgAECgYJDgAAAA==.',
Am='Ama:BAAALgAECgQJBQAAAA==.Amnorpse:BAABLgAECn8cAAIDAAgJix0PEQAkAgADAAgJix0PEQAkAgAAAA==.',
An='Anabana:BAAALgAECgQJCwAAAA==.Angler:BAABLgAECn8YAAMIAAkJNxcQDQBlAgAIAAkJNxcQDQBlAgAJAAEJrAW2gAAlAAAAAA==.Anruu:BAAALgAECgUJBQAAAA==.',
Ap='Appollis:BAAALgADCgQJBAAAAA==.Appropriate:BAAALgADCgMJAwAAAA==.',
Ar='Araleth:BAAALgAECgMJAwAAAA==.Arkthurus:BAAALgAECgYJDAAAAA==.Artumis:BAAALgADCgEJAQAAAA==.Arvitherejet:BAAALgAECgYJDgAAAA==.',
As='Aschern:BAAALgAECgYJDAAAAA==.Ashenfang:BAAALgAECgQJBAAAAA==.Ashijin:BAACLgAFFH8RAAIHAAUJTxpOGgBWAQAHAAUJTxpOGgBWAQAuAAQKfycAAgcACQlVIREmAI4CAAcACQlVIREmAI4CAAAA.Ashilyn:BAAALgAECgEJAQAAAA==.Ashoo:BAAALgADCgEJAQAAAA==.Astei:BAAALgADCgEJAQAAAA==.',
At='Ataxxius:BAAALgADCgMJAwAAAA==.Atheristina:BAAALgAECgQJBwABLgAECgcJGAAKAIcZAA==.Atroce:BAAALgAECgEJAwAAAA==.Atticu:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAABLgAECn82AAIGAAkJ6BheDgBlAgAGAAkJ6BheDgBlAgAAAA==.Auxilium:BAABLgAECn8cAAIHAAkJohWdQwCyAQAHAAkJohWdQwCyAQAAAA==.',
Aw='Awnen:BAAALgAECgYJEgAAAA==.',
Az='Aza:BAAALgADCgIJAgAAAA==.',
Ba='Backtrakk:BAAALgADCgMJAwAAAA==.Bahndis:BAAALgADCgcJDAAAAA==.Balebrew:BAAALgAECgkJCQABLgAECgkJNgALAAImAA==.Balethar:BAAALgAECgYJEwABLgAECgkJNgALAAImAA==.Ballador:BAAALgAECgYJDwAAAA==.Balluh:BAABLgAECn8rAAIMAAgJ/hZ6EgDPAQAMAAgJ/hZ6EgDPAQAAAA==.',
Be='Beartest:BAAALgAECgMJBAABLgAFFAUJBQANAJgBAA==.Beezen:BAACLgAFFH8TAAIJAAYJfBlGBACIAQAJAAYJfBlGBACIAQAuAAQKfyUAAgkACAm/IUcFADADAAkACAm/IUcFADADAAAA.Belara:BAAALgADCgYJBwAAAA==.Bellevo:BAAALgAECgQJBAABLgAECgkJKQAEAFMfAA==.Bellmage:BAABLgAECn8pAAMEAAkJUx/NDwDJAgAEAAkJUx/NDwDJAgAFAAEJxAlqHwAxAAAAAA==.Belttoash:BAABLgAECn8lAAIHAAcJ6BayYADCAQAHAAcJ6BayYADCAQAAAA==.Beneficiary:BAAALgAECgQJBQAAAA==.Bercey:BAABLgAECn8YAAIOAAkJGA4mPACrAQAOAAkJGA4mPACrAQAAAA==.Beybladetest:BAACLgAFFH8GAAMJAAMJRw3gGAC0AAAJAAMJxQjgGAC0AAAPAAIJkw+LGwCQAAAuAAQKfyAABA8ACQkVGgEWAFoCAA8ACAnmGgEWAFoCAAkABAmSGQYyAO0AAAgABAlQCvtPAI0AAAEuAAUUBQkFAA0AmAEA.',
Bi='Bigmang:BAAALgADCgYJBgAAAA==.Bigmayex:BAAALgADCgkJFgABLgAECgkJGgAQAMsaAA==.Bigscott:BAAALgAECgMJAwABLgAFFAUJBwAHAGkNAA==.Bilmuri:BAAALgADCgEJAQAAAA==.Binky:BAAALgADCgIJAgAAAA==.',
Bl='Blackbride:BAAALgAECgMJAwAAAA==.Blackfyre:BAAALgAECgIJBAAAAA==.Blackmage:BAAALgAFFAEJAQAAAA==.Blizzdrood:BAAALgADCgIJAgABLgAECggJLAAOAMkSAA==.Blizzlock:BAABLgAECn8sAAIOAAgJyRIkQQCaAQAOAAgJyRIkQQCaAQAAAA==.Blood:BAAALgAECgIJBAAAAA==.Bloodfeast:BAAALgADCgYJBgAAAA==.Blooms:BAAALgADCgIJAgAAAA==.Blurednuhtz:BAAALgADCgYJCQAAAA==.',
Bo='Bobcatross:BAAALgADCgYJBgAAAA==.Bohvicce:BAAALgADCgEJAQAAAA==.Bokudo:BAAALgADCgMJAwAAAA==.Bonezs:BAABLgAECn9CAAMKAAkJWiLbBAA9AwAKAAkJWiLbBAA9AwABAAUJvhO5NQDlAAAAAA==.Boogiepop:BAAALgAECgcJDQAAAA==.Bootylika:BAABLgAECn8bAAIDAAgJkxWiLgD3AQADAAgJkxWiLgD3AQAAAA==.Borislav:BAAALgADCgEJAQAAAA==.Bossvega:BAAALgAECgUJCAAAAA==.Boutdatbass:BAAALgAECgQJCgAAAA==.',
Br='Braxxar:BAAALgAECgYJEAAAAA==.Brendelf:BAAALgADCgcJCQAAAA==.Brett:BAAALgAECgEJAgAAAA==.Briellia:BAAALgAECgYJDgAAAA==.Bruggerlock:BAEALgADCgMJAwAAAA==.Bruhkakke:BAAALgAECgcJBgABLgAFFAYJDwARAPsQAA==.Bryagh:BAABLgAECn8gAAMSAAgJDhZ6GwCpAQASAAgJDhZ6GwCpAQATAAIJnwwiNwBfAAAAAA==.',
Bu='Bubbam:BAAALgADCgYJCAAAAA==.Bufferbug:BAAALgADCgkJFAAAAA==.Bugbear:BAAALgAECgYJBwAAAA==.Bulge:BAAALgADCgUJBQABLgAECggJGwAUAN4bAA==.Bullycow:BAABLgAECn8XAAIVAAYJJgXhGgAbAQAVAAYJJgXhGgAbAQAAAA==.Bushybrowsy:BAABLgAECn8qAAQWAAkJyxJ/BADrAQAWAAkJyxJ/BADrAQAOAAcJSwjKegAHAQAXAAMJRwJ5XQBWAAAAAA==.Buttercupz:BAABLgAECn8dAAIYAAkJlgtjHQCEAQAYAAkJlgtjHQCEAQAAAA==.',
['Bá']='Bámboo:BAAALgAECgEJAQAAAA==.',
['Bî']='Bîgdaddy:BAABLgAECn8nAAMZAAkJCRfAEgBjAgAZAAkJCRfAEgBjAgAaAAQJmgNqagCaAAAAAA==.',
Ca='Cacho:BAAALgAECggJCgAAAA==.Calevan:BAAALgAECgkJDwAAAA==.Candoran:BAAALgADCgMJAwAAAA==.Caracarn:BAAALgAECgcJCAAAAA==.Carpulations:BAABLgAECn8XAAIOAAYJEBivhABQAQAOAAYJEBivhABQAQAAAA==.',
Cc='Ccyll:BAAALgADCgkJEgAAAA==.',
Ce='Cerofewol:BAAALgADCgMJAwABLgAECgUJBwAbAAAAAA==.Cerridwen:BAABLgAECn8WAAIRAAYJzQcdLgAJAQARAAYJzQcdLgAJAQAAAA==.',
Ch='Chantini:BAAALgAECgUJBQAAAA==.Chartreuze:BAAALgAECgQJBgAAAA==.Chazmonk:BAAALgAECgEJAQABLgAFFAMJBQAZACQOAA==.Chazzie:BAACLgAFFH8FAAIZAAMJJA5MMQC/AAAZAAMJJA5MMQC/AAAuAAQKfxQAAhkACQlwGY4NAJoCABkACQlwGY4NAJoCAAAA.Cheonsul:BAAALgADCgQJBgAAAA==.Chexmix:BAAALgADCgUJBQAAAA==.Chia:BAACLgAFFH8XAAMcAAUJcBKoPwA4AQAcAAQJcBKoPwA4AQAdAAEJAAC9QAAAAAAuAAQKfyQAAhwACAlWH7EkACoCABwACAlWH7EkACoCAAAA.Chikn:BAABLgAECn8XAAIIAAgJ8xRYGAD7AQAIAAgJ8xRYGAD7AQAAAA==.Chirichiri:BAAALgADCgIJBAAAAA==.Chizu:BAAALgADCgUJBQABLgAFFAUJEwADAMogAA==.Chomboslice:BAABLgAECn8iAAMGAAkJXBxfEgB/AgAGAAkJXBxfEgB/AgAHAAMJOQxB5QB7AAAAAA==.',
Cl='Clary:BAAALgAECgEJAQABLgAECggJHgAPALEZAA==.Classy:BAAALgAECgYJBwAAAA==.',
Cm='Cmil:BAACLgAFFH8TAAMGAAUJoBO3DgBxAQAGAAUJoBO3DgBxAQAHAAIJyAFEZwBwAAAuAAQKfx8AAwYACAnxC8k4AJcBAAYACAnxC8k4AJcBAAcAAQnODcpCATMAAAAA.',
Co='Coffeebrew:BAAALgAECgYJDQABLgAECgcJDQAbAAAAAA==.Coffeecrem:BAAALgAECgcJDQAAAA==.Coffie:BAAALgADCgUJBQABLgAECgcJDQAbAAAAAA==.Coldnoodles:BAAALgAECgMJAwABLgAECgkJNAAJAOgfAA==.Combat:BAACLgAFFH8RAAIDAAUJARhqCwBKAQADAAUJARhqCwBKAQAuAAQKfx4AAgMACAk5HkoVAKMCAAMACAk5HkoVAKMCAAAA.Cornish:BAECLgAFFH8WAAIIAAYJFCJkAwBXAgAIAAYJFCJkAwBXAgAuAAQKfy4AAwgACQn3I3MBAJsDAAgACQn3I3MBAJsDAAkABQlbFUUuAAEBAAAA.Cornishpaste:BAEALgAECgQJBAABLgAFFAYJFgAIABQiAA==.Cosmo:BAAALgADCgcJCQABLgAECgkJFQAJAC8YAA==.',
Cr='Crackjaw:BAAALgAECgMJBgAAAA==.Crakmybitzup:BAAALgAECgUJBQAAAA==.Crockodk:BAAALgAECgEJAQAAAA==.',
Cu='Curserodlock:BAAALgAECgcJDwAAAA==.',
Cy='Cyanide:BAAALgAECgYJBwAAAA==.',
Da='Dabbinshamin:BAAALgAECgkJDwAAAA==.Dadanbing:BAAALgAECgYJBgABLgAFFAMJCAAZAEMPAA==.Daddyomg:BAAALgAECgYJCAABLgAFFAcJJAAaAIAbAA==.Dads:BAACLgAFFH8kAAMaAAcJgBtLBgC4AQAaAAYJZxlLBgC4AQAZAAQJKQh5MADCAAAuAAQKfxsAAxoACQkWJSMQAKgCABoABwm6JCMQAKgCABkACQloF74iAA4CAAAA.Daggertest:BAAALgADCgQJBAABLgAFFAUJBQANAJgBAA==.Dahai:BAAALgAECgMJAwAAAA==.Dakeyras:BAABLgAECn8iAAMeAAkJBBv7BQBtAgAeAAkJBBv7BQBtAgADAAMJIATRdwA0AAAAAA==.Darcevoker:BAACLgAFFH8LAAIfAAUJ7gdYDAAiAQAfAAUJ7gdYDAAiAQAuAAQKfyQAAh8ACAmrGOoNAFkCAB8ACAmrGOoNAFkCAAAA.Darcmonk:BAABLgAFFH8FAAIIAAQJgwS0HADUAAAIAAQJgwS0HADUAAABLgAFFAUJCwAfAO4HAA==.Darcpaladin:BAAALgAECgQJBQABLgAFFAUJCwAfAO4HAA==.Darcshaman:BAAALgAECgIJAgABLgAFFAUJCwAfAO4HAA==.Darkrune:BAABLgAECn8ZAAIcAAYJuhrTWABzAQAcAAYJuhrTWABzAQAAAA==.Darkschneide:BAAALgAECgQJBQAAAA==.Darthboo:BAAALgADCggJDAAAAA==.Darthtemplar:BAAALgAECgQJBAAAAA==.Davris:BAAALgAECgUJBwAAAA==.',
Db='Dbmagic:BAAALgAECgUJCAAAAA==.',
De='Dealsun:BAABLgAECn8bAAMOAAgJdBObRAD+AQAOAAgJdBObRAD+AQAXAAUJ2QdIOADTAAAAAA==.Decynth:BAAALgAECgcJCQAAAA==.Defne:BAAALgAECgEJAwAAAA==.Demodorn:BAECLgAFFH8XAAIgAAUJowVrAgCvAAAgAAUJowVrAgCvAAAuAAQKfycAAiAACAmgFE4IAPgBACAACAmgFE4IAPgBAAAA.Demondudez:BAAALgAECgUJCwAAAA==.Demonikat:BAAALgADCgEJAQAAAA==.Demonsurfin:BAAALgAECgUJBQAAAA==.Demussi:BAAALgAECgEJAQAAAA==.Demyst:BAACLgAFFH8SAAMZAAUJxw9WDwB5AQAZAAUJxw9WDwB5AQAaAAUJlRAeFgAdAQAuAAQKfyEAAxoACQlYHykSAJICABoACQlYHykSAJICABkAAgmmDd+VADgAAAAA.Deria:BAAALgAECgEJAQAAAA==.Devilsparda:BAAALgAECgMJAwAAAA==.Deweey:BAAALgAECgUJCQAAAA==.Dezeraz:BAECLgAFFH8MAAIfAAQJbBwYBwB+AQAfAAQJbBwYBwB+AQAuAAQKfyMAAh8ACAkDJv4BAFsDAB8ACAkDJv4BAFsDAAEuAAUUBgkWAAgAFCIA.',
Dh='Dhecaye:BAAALgADCgkJDwABLgAFFAMJBAAbAAAAAA==.',
Di='Dieuscum:BAAALgAECgUJBQAAAA==.Diksneeze:BAAALgADCgUJCAAAAA==.Disengage:BAAALgAECgkJAwABLgAFFAUJEQADAAEYAA==.Dislogic:BAABLgAECn8kAAMOAAkJbiL2CADeAgAOAAgJbiL2CADeAgAXAAQJTSCiGwBwAQAAAA==.',
Dl='Dlorpglorp:BAAALgAECgIJAgABLgAECgcJHwAEAEMgAA==.',
Do='Dobbie:BAAALgADCgUJBQAAAA==.Donkey:BAAALgAECgcJCgAAAA==.Donmega:BAAALgAECgMJAwAAAA==.Doraleous:BAABLgAECn8fAAIGAAgJAx7rDwBRAgAGAAgJAx7rDwBRAgAAAA==.Dotzmybitzup:BAACLgAFFH8NAAMOAAQJmx6HHgAKAQAOAAQJmx6HHgAKAQAXAAEJRQ2iGgBHAAAuAAQKfzYABA4ACAmNJRoJAN0CAA4ACAmNJRoJAN0CABYAAglqEzEdAIgAABcAAQlXDm9jAEgAAAEuAAUUBQkQABIABxwA.Dougalleone:BAACLgAFFH8QAAIQAAUJoyLpCwBcAQAQAAUJoyLpCwBcAQAuAAQKfyUAAxAACQmJIocHABgDABAACQmJIocHABgDACEAAQmtEfsdAD0AAAAA.',
Dr='Draci:BAAALgADCgEJAQAAAA==.Drdumbottles:BAAALgAECgUJBQAAAA==.Dreadknott:BAACLgAFFH8KAAIcAAMJFxAYawDfAAAcAAMJFxAYawDfAAAuAAQKfysAAhwACQleHacbAF4CABwACQleHacbAF4CAAAA.Dreadxknight:BAAALgADCgMJAwAAAA==.Drekim:BAABLgAECn8UAAISAAUJryAbLgBRAQASAAUJryAbLgBRAQAAAA==.Dreko:BAAALgAECgMJAwAAAA==.Drezzakmage:BAACLgAFFH8KAAIEAAQJMwiCRgApAQAEAAQJMwiCRgApAQAuAAQKfyIAAgQACQldFl9gABoCAAQACQldFl9gABoCAAAA.Drezzakzdh:BAAALgADCgYJBgABLgAFFAQJCgAEADMIAA==.Druidiac:BAAALgADCgYJEwABLgAECgkJLQAYAIgaAA==.',
Du='Dugren:BAAALgAECgkJCQAAAA==.',
Ed='Edgelf:BAAALgADCgMJAwAAAA==.',
El='Elaidare:BAAALgAECggJCgABLgAECggJGgAgAIsNAA==.Elaidine:BAABLgAECn8aAAMgAAgJiw2wDQAhAQAgAAgJiw2wDQAhAQAiAAEJAADG+wAAAAAAAA==.Elisabetta:BAAALgADCgMJAwAAAA==.Elizalex:BAAALgAECgIJBAAAAA==.',
Em='Emagdne:BAAALgADCgMJAgAAAA==.Empath:BAAALgADCgQJBQAAAA==.',
En='Enferno:BAAALgAECgYJDgABLgAECggJLAAOAMkSAA==.Enfernum:BAAALgADCgEJAQABLgAECggJLAAOAMkSAA==.Enolad:BAAALgADCgcJBwABLgAECgcJDAAbAAAAAA==.Entrapy:BAAALgAECgEJAQAAAA==.',
Er='Eradius:BAAALgADCgIJAgAAAA==.Errai:BAABLgAECn8rAAIOAAkJFR+VDgCkAgAOAAkJFR+VDgCkAgAAAA==.',
Es='Estefania:BAAALgAECgEJAQAAAA==.',
Eu='Eureka:BAABLgAECn8XAAIBAAkJshd3DgAjAgABAAkJshd3DgAjAgAAAA==.',
Ev='Evilnapkin:BAAALgAECgQJEQAAAA==.Evion:BAABLgAECn8eAAIjAAkJDxqDLwDzAQAjAAkJDxqDLwDzAQAAAA==.',
Ey='Eyedoll:BAAALgAECgEJAQAAAA==.Eyez:BAAALgADCgIJAgAAAA==.',
Fa='Faelthorn:BAAALgADCgQJBAAAAA==.Faemalis:BAAALgAECgEJAQAAAA==.Farseer:BAAALgADCgMJAwAAAA==.',
Fe='Feardoctor:BAAALgAECgQJCAAAAA==.Feelthepower:BAABLgAECn8WAAIEAAYJ2xhQeABKAQAEAAYJ2xhQeABKAQAAAA==.',
Fl='Flavorfrenzy:BAAALgADCgUJBQABLgADCgkJCQAbAAAAAA==.',
Fo='Fourimborniy:BAAALgAECgcJCwAAAA==.',
Fr='Frenzi:BAAALgADCgEJAQAAAA==.Friendulum:BAAALgAECgcJBwAAAA==.Fries:BAEALgAECgEJAQABLgAFFAQJBwAOAKYPAA==.Frostey:BAAALgADCgEJAQAAAA==.',
Fu='Fuzzsicle:BAAALgAECgYJCQAAAA==.Fuzzydìcê:BAAALgAECgUJCAAAAA==.',
['Fá']='Fáelen:BAABLgAECn8fAAIkAAgJOB6pBgCLAgAkAAgJOB6pBgCLAgAAAA==.',
Ga='Galang:BAAALgAECgMJBQAAAA==.Gangactivity:BAAALgAECgQJCwABLgAFFAMJCAAJANQbAA==.Garm:BAAALgAECgEJAwAAAA==.Garrt:BAABLgAECn8UAAIkAAcJoxceCwCqAQAkAAcJoxceCwCqAQAAAA==.Gartalvanise:BAAALgAECgkJDgAAAA==.Gavinrad:BAAALgAECgYJEQAAAA==.',
Ge='Gep:BAAALgAECgcJEgAAAA==.',
Gl='Glaalinix:BAAALgADCgkJGgAAAA==.Glaciiel:BAAALgAECgMJAwAAAA==.Globbie:BAAALgADCgMJAwAAAA==.',
Go='Goku:BAAALgAECgQJBQAAAA==.Goobman:BAAALgADCgQJBQABLgAFFAMJCAAKABgaAA==.Goodman:BAABLgAECn8tAAIHAAkJ+B2OEgCYAgAHAAkJ+B2OEgCYAgAAAA==.Goomei:BAACLgAFFH8OAAIJAAQJFRzHBwBRAQAJAAQJFRzHBwBRAQAuAAQKfzIAAgkACQmnIqoCABMDAAkACQmnIqoCABMDAAEuAAUUBwkWACIAwBoA.Goomi:BAACLgAFFH8WAAIiAAcJwBp8BQAeAgAiAAcJwBp8BQAeAgAuAAQKfyEAAiIACQk+IxADAJ4DACIACQk+IxADAJ4DAAAA.Gordius:BAAALgADCgEJAQAAAA==.Gorok:BAAALgAECgQJCgAAAA==.Goybeam:BAAALgADCgcJCQAAAA==.',
Gr='Gravykin:BAABLgAECn8WAAIkAAkJcA01DACWAQAkAAkJcA01DACWAQAAAA==.Grayfoxrun:BAAALgADCgUJBQAAAA==.Greatbooty:BAABLgAECn8fAAIEAAgJNBQxQwDQAQAEAAgJNBQxQwDQAQAAAA==.Grecko:BAAALgADCgUJBQAAAA==.Gremmi:BAAALgAECgEJBQAAAA==.Greygavel:BAABLgAECn8TAAIlAAYJuiKgBQDbAQAlAAYJuiKgBQDbAQAAAA==.Grimmknight:BAAALgADCgEJAQAAAA==.Grosgland:BAAALgADCgEJAQAAAA==.Groundbeéf:BAACLgAFFH8WAAIVAAYJHCLOAAC/AQAVAAYJHCLOAAC/AQAuAAQKfykAAhUACAkJJvsAAH4DABUACAkJJvsAAH4DAAAA.Groundzero:BAAALgADCgUJBQAAAA==.Groztrazztok:BAAALgAECgYJEwAAAA==.Grungulus:BAAALgAECgcJEwAAAA==.',
Gu='Guineapig:BAEBLgAECn8UAAIHAAcJLyTdMABfAgAHAAcJLyTdMABfAgAAAA==.Gundral:BAAALgADCgIJAgAAAA==.Gunnysack:BAAALgADCggJDgAAAA==.Guzmo:BAAALgAECgEJAQABLgAECgUJBgAbAAAAAA==.',
Gy='Gyx:BAAALgAECgQJCAAAAA==.',
Ha='Haiku:BAAALgAECgEJAQAAAA==.Handanir:BAABLgAECn8sAAIKAAkJXyF8BABFAwAKAAkJXyF8BABFAwAAAA==.Harie:BAABLgAECn8fAAIEAAYJoQ4tjwAfAQAEAAYJoQ4tjwAfAQAAAA==.Hasbula:BAAALgAECgQJBAAAAA==.Hatebound:BAAALgAECgIJAgAAAA==.',
He='Hearthcliff:BAAALgAECgQJBwAAAA==.Heihei:BAAALgADCgYJDAAAAA==.Heiny:BAACLgAFFH8HAAMcAAMJbCDZVAAGAQAcAAMJ2xrZVAAGAQAlAAIJuh2LCgCzAAAuAAQKfyIABCUACQlNJq8AACEDACUACQk7JK8AACEDABwACAltJpAIAPgCAB0ABgkEET8mAA0BAAAA.Heinyheinyho:BAABLgAECn8uAAMGAAgJPiSyCADkAgAGAAgJPiSyCADkAgALAAUJOiHaDgB9AQABLgAFFAMJBwAcAGwgAA==.',
Hi='Hielle:BAAALgADCgkJCQAAAA==.Highguard:BAAALgADCgcJBwAAAA==.Himothy:BAAALgAECgEJBAAAAA==.',
Ho='Hoid:BAAALgAECgEJAgAAAA==.Holy:BAAALgADCgYJBgAAAA==.Holysword:BAEALgADCgYJBgABLgAECgQJBQAbAAAAAA==.Holytest:BAABLgAFFH8FAAINAAUJmAFBDwAHAQANAAUJmAFBDwAHAQAAAA==.Hoofmetoo:BAABLgAECn8qAAIcAAgJvR2pIgA1AgAcAAgJvR2pIgA1AgAAAA==.Howboudah:BAAALgADCggJCAAAAA==.',
Hu='Hulkgirl:BAAALgADCgEJAQAAAA==.Hulzar:BAABLgAECn8YAAIDAAcJlRxJGgDMAQADAAcJlRxJGgDMAQAAAA==.',
Hy='Hypocrisy:BAAALgAECgkJBgAAAA==.',
['Hô']='Hôlyblight:BAAALgAECgEJAQABLgAFFAQJDgAaAHIYAA==.',
Ic='Iceflare:BAABLgAECn8ZAAMEAAgJihbfVAA5AgAEAAgJihbfVAA5AgAFAAQJ7gLmEwCHAAAAAA==.',
Id='Idotyouto:BAABLgAECn8vAAIEAAgJnRvSUgA/AgAEAAgJnRvSUgA/AgAAAA==.',
Ig='Igris:BAAALgAECgQJCgAAAA==.',
Ih='Ihavewater:BAAALgADCgkJCQAAAA==.',
Il='Ilbryen:BAAALgAECgUJBQABLgAFFAUJEwADAMogAA==.Illidori:BAABLgAECn8VAAIiAAcJ2ge2dgDgAAAiAAcJ2ge2dgDgAAAAAA==.Illidrag:BAABLgAECn8VAAImAAkJhRFaGABYAQAmAAkJhRFaGABYAQAAAA==.Ilovemoo:BAAALgAECgMJAwAAAA==.',
Im='Imblind:BAAALgADCgEJAQABLgAFFAUJEAAJABQWAA==.Imladris:BAAALgAECgYJDgAAAA==.Immortea:BAAALgAECgkJBgAAAA==.Immòrtlzed:BAACLgAFFH8WAAMfAAUJMCK1BwDJAQAfAAUJMCK1BwDJAQATAAEJfQf5CQBLAAAuAAQKfyYAAh8ACAnwIDYFAIICAB8ACAnwIDYFAIICAAAA.',
In='Invective:BAAALgAECgMJAwAAAA==.',
Is='Isharn:BAAALgADCgMJAwAAAA==.',
Iz='Izzyumi:BAABLgAECn8XAAIjAAcJVgy/ZgAaAQAjAAcJVgy/ZgAaAQAAAA==.',
Ja='Jabo:BAAALgADCgMJAwABLgAECgUJDAAbAAAAAA==.Jadelin:BAAALgAECgIJAgABLgAECgYJGgAEAOkKAA==.Jaxek:BAABLgAECn8vAAIkAAkJxCIlAQASAwAkAAkJxCIlAQASAwAAAA==.Jaxs:BAACLgAFFH8PAAIZAAYJSxqlBQDxAQAZAAYJSxqlBQDxAQAuAAQKfyAAAhkACAlAG5kVAGgCABkACAlAG5kVAGgCAAAA.Jaylen:BAAALgAECgYJEwAAAA==.Jaymo:BAAALgAECgYJEQAAAA==.',
Je='Jebke:BAAALgAECgMJBQABLgAECgYJBwAbAAAAAA==.Jeffurry:BAAALgADCgIJAgAAAA==.Jeminia:BAAALgAECgUJCgAAAA==.Jenifur:BAABLgAECn8VAAIKAAYJrQtvXgDVAAAKAAYJrQtvXgDVAAAAAA==.Jennae:BAAALgADCgEJAQAAAA==.',
Jh='Jhope:BAABLgAFFH8IAAIPAAMJkA2iKgDHAAAPAAMJkA2iKgDHAAAAAA==.',
Ji='Jinkusu:BAAALgADCgMJAwABLgAECgkJGwAPACMdAA==.',
Jm='Jml:BAACLgAFFH8UAAIiAAUJDyQ7CQCWAQAiAAUJDyQ7CQCWAQAuAAQKfx4AAiIACQnSIQAFAHYDACIACQnSIQAFAHYDAAAA.',
Jo='Jopha:BAACLgAFFH8VAAMDAAYJSh41BwB5AQADAAUJfiE1BwB5AQACAAIJhAltHAB6AAAuAAQKfyoAAwMACAlVJQAGAEcDAAMACAkzJQAGAEcDAAIABwmYH/IEAJQCAAAA.Jophr:BAAALgAECgQJAgABLgAFFAYJFQADAEoeAA==.',
Jp='Jpbruiser:BAACLgAFFH8FAAIHAAIJfhuNTAC5AAAHAAIJfhuNTAC5AAAuAAQKfzsAAgcACAmXI5oOALkCAAcACAmXI5oOALkCAAAA.',
Ju='Judged:BAAALgAECgYJEQAAAA==.Juggalette:BAAALgADCgIJAgAAAA==.Jumpn:BAAALgAFFAEJAQABLgAFFAUJEwAdAEIbAA==.Jumpndeath:BAACLgAFFH8TAAIdAAUJQhsTDQAuAQAdAAUJQhsTDQAuAQAuAAQKfysAAx0ACQlaIgsPAMQBAB0ACAnoIgsPAMQBABwABwnlG5F+AIYBAAAA.Jumpnpunch:BAABLgAECn8lAAQPAAgJaxwBGgA0AgAPAAcJQBwBGgA0AgAJAAgJ7A89HwBgAQAIAAcJoQwHOAALAQABLgAFFAUJEwAdAEIbAA==.Junknugget:BAAALgADCgYJBgAAAA==.Justgetme:BAABLgAECn82AAMLAAkJAiZNAABmAwALAAkJAiZNAABmAwAHAAIJAA6lGwFjAAAAAA==.',
Jw='Jwad:BAABLgAECn8eAAMOAAYJ8RZMXwBDAQAOAAUJ8RZMXwBDAQAXAAIJ8QwEUwB1AAAAAA==.',
Ka='Kaan:BAAALgAECgEJAwAAAA==.Kaariel:BAAALgADCgcJCgAAAA==.Kabo:BAAALgADCgUJCQABLgAFFAUJEAAcADIjAA==.Kagger:BAACLgAFFH8NAAIHAAQJ9B0zEgB0AQAHAAQJ9B0zEgB0AQAuAAQKfzsAAgcACQkuI+8EAH0DAAcACQkuI+8EAH0DAAAA.Kaiser:BAAALgADCgcJDAAAAA==.Kaitu:BAAALgAECgYJCwABLgAECgcJBwAbAAAAAA==.Kake:BAAALgAECgQJBAABLgAFFAMJAwAbAAAAAA==.Kalloh:BAABLgAECn8oAAMOAAYJNxXEagApAQAOAAYJNxXEagApAQAXAAIJ4RWQHQB6AAAAAA==.Kalorth:BAAALgADCgcJBwAAAA==.Kardoroth:BAACLgAFFH8MAAIcAAQJLyXLEgCqAQAcAAQJLyXLEgCqAQAuAAQKfzUAAhwACQmuJiICAGIDABwACQmuJiICAGIDAAAA.Karibo:BAAALgADCgcJDAAAAA==.Karnaege:BAAALgADCgMJAwAAAA==.Karîba:BAACLgAFFH8XAAQcAAUJQhx7FwBHAQAcAAQJxxt7FwBHAQAdAAMJPxO/DgB+AAAlAAEJMgtiEgBAAAAuAAQKfy0AAxwACAnRH1IfAMUCABwACAnRH1IfAMUCAB0AAQkrCTVNABwAAAAA.Kassi:BAAALgADCgEJAQAAAA==.Kayfree:BAAALgAECgUJCgAAAA==.Kaõtik:BAAALgAECgkJCgAAAA==.',
Ke='Keerrilee:BAABLgAECn8XAAIJAAkJ8BruHAB2AQAJAAkJ8BruHAB2AQAAAA==.Kefka:BAAALgAECgQJBQAAAA==.Keirine:BAAALgAECgEJAwAAAA==.Kelfrost:BAAALgAECgIJAgAAAA==.Kelknight:BAABLgAECn8YAAMdAAQJ0h6THwACAQAcAAQJsxpVuwAMAQAdAAMJpR+THwACAQAAAA==.Kelsaz:BAACLgAFFH8WAAMjAAUJeBl5CwAGAQAMAAUJOxjICQBSAQAjAAMJchV5CwAGAQAuAAQKfx8ABCMACAkqIzISAKYCACMABwlIIzISAKYCACcABglBGPdGADgBAAwABAn2FuQxAL4AAAAA.Kelsi:BAABLgAECn8VAAIJAAkJLxgWGAChAQAJAAkJLxgWGAChAQAAAA==.Kenný:BAAALgAECgEJAQAAAA==.Kerrìgàn:BAACLgAFFH8bAAIgAAYJaBf3AACGAQAgAAYJaBf3AACGAQAuAAQKfy0AAyAACQlMIWkCANYCACAACQlMIWkCANYCACYAAQlKDXVNADAAAAAA.Kestral:BAACLgAFFH8MAAMSAAUJWwEkLQDIAAASAAUJWwEkLQDIAAAfAAMJ6QibGACqAAAuAAQKfyYAAx8ACAkMFCoUAAMCAB8ACAkMFCoUAAMCABIAAwn7CulTAIUAAAAA.Keynis:BAAALgADCgEJAQAAAA==.',
Kh='Khalisi:BAAALgAECgUJCQAAAA==.Khejan:BAAALgADCgMJAwAAAA==.Khrask:BAAALgADCgIJAgABLgAFFAUJEwADAMogAA==.',
Ki='Kiell:BAAALgAECgYJBwAAAA==.Kinuyo:BAAALgAECgQJBAAAAA==.Kirali:BAAALgAECgYJBgAAAA==.Kiwipie:BAAALgAECgQJBAAAAA==.',
Kn='Knottyjack:BAAALgADCgMJAwAAAA==.',
Ko='Kookiie:BAACLgAFFH8WAAMmAAYJ8SAVAQDaAQAmAAYJ8SAVAQDaAQAiAAIJWQ19KwCYAAAuAAQKfyUAAyYACAkTIb4JAMYCACYABwnbJb4JAMYCACIACAkuHL0kAHYCAAAA.Kookiiez:BAAALgAECgQJBAAAAA==.Koom:BAAALgADCgYJBQAAAA==.Kosi:BAAALgAECgQJBAABLgAFFAQJCgASANYUAA==.Kosian:BAABLgAECn8YAAILAAcJdA48GAAFAQALAAcJdA48GAAFAQAAAA==.Kosigan:BAAALgAECgIJAgABLgAFFAQJCgASANYUAA==.',
Kp='Kpop:BAAALgADCgEJAQAAAA==.',
Kr='Krepuscular:BAAALgAECgMJAwAAAA==.Kromdor:BAABLgAECn8YAAIXAAgJSxoKBgBxAgAXAAgJSxoKBgBxAgAAAA==.Krosis:BAABLgAECn8YAAIcAAkJqRzwOABTAgAcAAkJqRzwOABTAgAAAA==.Krumee:BAAALgADCgYJBgAAAA==.',
Kt='Kthríss:BAAALgADCgMJAwAAAA==.',
Ku='Kungscott:BAAALgAECgEJAwABLgAFFAUJBwAHAGkNAA==.Kuromi:BAAALgAECgYJCAAAAA==.',
Ky='Kynei:BAABLgAECn8WAAIiAAgJsh45HAAnAgAiAAgJsh45HAAnAgAAAA==.',
La='Lacasis:BAAALgADCgUJBQABLgAECgcJBwAbAAAAAA==.Larra:BAACLgAFFH8TAAMRAAUJHRanDQCeAQARAAUJ0xWnDQCeAQANAAMJmgv8CADYAAAuAAQKfyEABA0ACQnsGioPAG8CAA0ACAlrHSoPAG8CABgABgnvGzMtAHUBABEABgkQDlokAE0BAAAA.',
Le='Leman:BAAALgADCgkJFAAAAA==.Lemoncrisp:BAAALgAECgEJAQAAAA==.Leprocylarry:BAAALgADCgcJBwAAAA==.Letos:BAAALgAECgcJEgAAAA==.Levelmoo:BAAALgAECgYJBgAAAA==.Levitas:BAABLgAECn8tAAIeAAkJKRPUCwDhAQAeAAkJKRPUCwDhAQAAAA==.Lewieballz:BAAALgADCgMJAwABLgAECggJHgAbAAAAAA==.',
Li='Liberater:BAAALgAECgEJAQAAAA==.Liljit:BAAALgAECgcJDgAAAA==.Lithel:BAAALgAECgcJCAAAAA==.',
Lo='Loaded:BAAALgAECgEJAQAAAA==.Lockxeno:BAABLgAECn8YAAMOAAgJ8hjoLADnAQAOAAcJ8hjoLADnAQAXAAEJAAArQgAAAAAAAA==.Lodidodii:BAAALgAECggJEgAAAA==.Logics:BAACLgAFFH8IAAIYAAQJoBnVCwBZAQAYAAQJoBnVCwBZAQAuAAQKfysAAhgACQkgI3sDAPsCABgACQkgI3sDAPsCAAAA.Lon:BAABLgAECn8YAAIJAAgJxxJlLAB9AQAJAAgJxxJlLAB9AQAAAA==.Longsham:BAAALgADCgEJAQAAAA==.Lostea:BAAALgADCgUJBQABLgAECggJGQASAJQXAA==.Lostmylimbs:BAACLgAFFH8IAAIdAAQJJQndCgDQAAAdAAQJJQndCgDQAAAuAAQKfyQAAh0ACAnXF7sTANMBAB0ACAnXF7sTANMBAAEuAAUUBgkbACAAaBcA.Lostmyvigor:BAAALgAFFAMJAwAAAA==.Lostvoker:BAABLgAECn8ZAAMSAAgJlBe8FQAsAgASAAgJlBe8FQAsAgATAAUJehDrIgATAQAAAA==.Loueballz:BAAALgAECggJHgAAAQ==.Lowvice:BAAALgADCgEJAQAAAA==.',
Lu='Lucarad:BAABLgAECn8rAAIJAAgJ+BgQEgDhAQAJAAgJ+BgQEgDhAQAAAA==.Lucerfer:BAAALgADCgUJBwAAAA==.Lucivia:BAABLgAECn8xAAIWAAkJTRoAAwAtAgAWAAkJTRoAAwAtAgAAAA==.Lumafist:BAACLgAFFH8IAAIJAAMJ1BthEAD9AAAJAAMJ1BthEAD9AAAuAAQKfy8AAgkACQnQIRgFAMYCAAkACQnQIRgFAMYCAAAA.Lunirae:BAAALgADCgYJBgAAAA==.',
['Lè']='Lènneth:BAABLgAECn8tAAMNAAkJgh0iBwC7AgANAAkJgh0iBwC7AgAYAAIJzBB0TQByAAAAAA==.',
['Lí']='Líghtning:BAAALgAECggJDgAAAA==.',
['Lø']='Løstdruid:BAAALgADCgEJAQABLgAECgUJCQAbAAAAAA==.Løstpala:BAAALgAECgUJCQAAAA==.',
Ma='Mahiru:BAAALgADCgMJAwAAAA==.Makkaflocka:BAAALgAECgUJBQABLgAECggJIAAiACchAA==.Malleus:BAAALgADCgUJBQAAAA==.Malytheris:BAABLgAECn8YAAMLAAgJZA4cEgBMAQALAAgJZA4cEgBMAQAHAAEJzgWnRwErAAAAAA==.Marqis:BAAALgAECgEJAQAAAA==.Mattshanu:BAACLgAFFH8OAAIaAAQJFxgSEwAtAQAaAAQJFxgSEwAtAQAuAAQKfx4AAhoACQktHrsUAHgCABoACQktHrsUAHgCAAAA.Mayalaran:BAAALgADCgcJDwAAAA==.Mazgruug:BAAALgAECgcJCgAAAA==.Mazkova:BAAALgAECggJEQAAAA==.Mazur:BAABLgAECn8hAAIHAAgJdCE3GAByAgAHAAgJdCE3GAByAgAAAA==.',
Mc='Mcmonkton:BAAALgAECgcJDAAAAA==.',
Me='Meirah:BAAALgADCgYJBAAAAA==.Mekkaweepz:BAAALgADCgUJBQAAAA==.Melaan:BAABLgAECn8YAAIKAAYJhxkNMACZAQAKAAYJhxkNMACZAQAAAA==.Melinadra:BAAALgAECgEJAQAAAA==.Meowmixx:BAAALgADCgYJBgAAAA==.Meowssa:BAECLgAFFH8MAAIoAAQJhx/uAgB6AQAoAAQJhx/uAgB6AQAuAAQKfysAAygACQkFJa8AAE0DACgACQkFJa8AAE0DACQAAglXEZ0lAG4AAAAA.',
Mi='Midori:BAAALgAECgEJAQAAAA==.Mindleseye:BAAALgADCgQJBgAAAA==.Mindlesscon:BAABLgAECn8WAAMVAAYJ0x7YDAD1AQAVAAYJph3YDAD1AQAaAAUJXB6QPABaAQAAAA==.Minislayer:BAAALgAECgcJEQAAAA==.Minyprayers:BAACLgAFFH8bAAMYAAYJ6BWACQBtAQAYAAUJaBqACQBtAQANAAEJvAq8IQBSAAAuAAQKfygAAhgACQkTJUcKAN4CABgACQkTJUcKAN4CAAAA.Minywon:BAAALgADCgcJCgABLgAFFAYJGwAYAOgVAA==.Misosalty:BAABLgAECn80AAMJAAkJ6B9JBADbAgAJAAkJ6B9JBADbAgAPAAUJ1xchOQDbAAAAAA==.Misowet:BAAALgADCgYJCQABLgAECgkJNAAJAOgfAA==.',
Ml='Mlorpglorp:BAABLgAECn8fAAIEAAcJQyB7PQCCAgAEAAcJQyB7PQCCAgAAAA==.',
Mo='Mobaye:BAAALgAECgEJAQAAAA==.Mohjito:BAABLgAECn8yAAMJAAkJ7RuUCQBiAgAJAAkJ7RuUCQBiAgAPAAUJHhGbPQDJAAAAAA==.Mojojojoz:BAAALgADCgUJBQAAAA==.Monkisbad:BAABLgAECn8uAAIPAAgJuyNiDADJAgAPAAgJuyNiDADJAgAAAA==.Monkma:BAAALgAECgIJAgAAAA==.Moonfire:BAAALgADCgcJDgAAAA==.Moose:BAAALgADCgYJBgAAAA==.Mooshanu:BAAALgADCgcJDAABLgAFFAQJDgAaABcYAA==.Morguth:BAACLgAFFH8SAAMjAAUJZBeIFwBPAQAjAAUJZBeIFwBPAQAnAAIJUQCtIwBdAAAuAAQKfx0ABCMACQl7HSUUAJUCACMACQl7HSUUAJUCACcABAkeBLVnAKAAAAwAAgliDypLADcAAAAA.Moriaug:BAAALgAECgUJBgABLgAFFAQJBwAEACkeAA==.Moriko:BAABLgAECn8UAAIRAAcJTAy0KwA9AQARAAcJTAy0KwA9AQAAAA==.',
Mu='Muggy:BAAALgAECgEJBAAAAA==.Murky:BAACLgAFFH8FAAIQAAIJrxP1HgCoAAAQAAIJrxP1HgCoAAAuAAQKfyoAAhAACAk6HjwIAFoCABAACAk6HjwIAFoCAAAA.Musicmichael:BAAALgAECgYJCQAAAA==.',
['Mî']='Mîyagî:BAAALgAECgcJCQAAAA==.',
['Mö']='Mööbs:BAABLgAECn8qAAMfAAgJKQfwFgAUAQAfAAgJKQfwFgAUAQASAAYJfQYeSwCnAAAAAA==.',
Na='Namad:BAAALgAECgYJDwAAAA==.Nancybrew:BAABLgAECn8mAAMJAAkJoh+SBwCLAgAJAAkJoh+SBwCLAgAIAAIJdRJ3WABtAAAAAA==.Nathric:BAAALgADCgUJBQAAAA==.Navajo:BAAALgAECgcJEwAAAA==.',
Ne='Neature:BAAALgADCgMJAwAAAA==.Neoma:BAABLgAECn8YAAIOAAYJ7QtbfgD/AAAOAAYJ7QtbfgD/AAAAAA==.Nesqwik:BAAALgAECgQJCAAAAA==.Nevan:BAABLgAECn8kAAMGAAkJYCP3BQDwAgAGAAkJYCP3BQDwAgAHAAQJdw9YpgDgAAAAAA==.Neverender:BAAALgAECgEJAgABLgAECgYJDgAbAAAAAA==.Newlock:BAAALgAECgQJBAAAAA==.Nexi:BAAALgAECgMJAwAAAA==.',
Ni='Niang:BAAALgADCgQJBAAAAA==.Nidalee:BAAALgAECgYJDwAAAA==.Nippyvixen:BAAALgAECgEJAQAAAA==.Nishu:BAAALgADCgMJAwAAAA==.',
No='Noochallange:BAABLgAECn8tAAIhAAkJJCEyAQDSAgAhAAkJJCEyAQDSAgAAAA==.Norex:BAACLgAFFH8NAAQcAAUJmRcVMABSAQAcAAQJmRcVMABSAQAlAAEJoQNoEgBAAAAdAAEJAAAPOAAAAAAuAAQKfyEAAxwACQklE9VaAOEBABwACQmyEtVaAOEBAB0ABgmfCLosANkAAAAA.Norm:BAAALgAECgYJCwAAAA==.Notekk:BAAALgAECgQJBwAAAA==.Nottygerbil:BAAALgAECgMJAwAAAA==.',
Nu='Nuggie:BAABLgAECn8gAAMOAAkJ3xnZHgAuAgAOAAgJ3xnZHgAuAgAXAAEJAADGYgBJAAAAAA==.Nurf:BAAALgADCgMJAwAAAA==.Nurgal:BAAALgAECgYJCAAAAA==.Nutlips:BAAALgADCgUJCwAAAA==.',
Ny='Nylariaa:BAAALgAECgYJEgAAAA==.Nymia:BAABLgAECn8nAAMKAAkJMRyUFgBLAgAKAAkJMRyUFgBLAgABAAEJthgJXgBJAAAAAA==.',
['Næ']='Næon:BAABLgAECn8gAAIIAAkJcxjtEAAxAgAIAAkJcxjtEAAxAgAAAA==.',
Ob='Oblake:BAABLgAECn8YAAIQAAcJkBQmIQDwAQAQAAcJkBQmIQDwAQAAAA==.',
Oc='Octosloth:BAAALgADCgEJAQAAAA==.',
Oh='Ohhashbrowns:BAAALgADCgcJBwAAAA==.',
Ok='Oku:BAAALgADCgcJBgAAAA==.',
Ol='Oldmagic:BAAALgAECgYJEgAAAA==.Olizza:BAAALgAECgIJAgABLgAECgcJHAAjAHENAA==.',
Om='Omgimabeast:BAAALgAECgYJCAAAAA==.',
On='Onieva:BAAALgAECgkJDgAAAA==.',
Oo='Ooglaboogla:BAABLgAECn8zAAMaAAkJAR0vCQCGAgAaAAkJAR0vCQCGAgAZAAIJhxyRggCJAAAAAA==.',
Or='Oriah:BAAALgADCgYJBgAAAA==.Orions:BAAALgADCgQJBAAAAA==.',
Os='Osserc:BAAALgADCgYJBgAAAA==.',
Ox='Oxyrotten:BAABLgAECn8bAAIcAAYJ9gzhjwD8AAAcAAYJ9gzhjwD8AAAAAA==.',
Pa='Pablo:BAABLgAECn82AAMMAAkJlCGrAwDJAgAMAAkJlCGrAwDJAgAnAAEJZREShwA1AAAAAA==.Pancho:BAABLgAECn8bAAIJAAkJeBeRDAAuAgAJAAkJeBeRDAAuAgAAAA==.Pandra:BAAALgADCgEJAQAAAA==.Panttyraider:BAAALgAFFAIJAgAAAA==.Panzeria:BAABLgAECn8dAAIYAAcJPSU8CQDwAgAYAAcJPSU8CQDwAgAAAA==.Papito:BAAALgAFFAEJAQAAAA==.Pathryis:BAAALgAECgYJBgAAAA==.Pawsome:BAAALgADCgIJAgAAAA==.',
Pl='Plank:BAAALgAECgUJBwAAAA==.',
Pm='Pmon:BAAALgADCgEJAQAAAA==.',
Po='Pongo:BAAALgAECgUJCQAAAA==.Ponkofox:BAABLgAECn8dAAIVAAgJQBQJDgDcAQAVAAgJQBQJDgDcAQAAAA==.',
Pr='Prah:BAAALgAECgcJDAAAAA==.Prepared:BAAALgAECgIJAgAAAA==.Prise:BAAALgAECgMJBgAAAA==.Prisefather:BAAALgAECgYJCgAAAA==.Prizefighter:BAAALgAECgYJDQAAAA==.Proditus:BAAALgAECgMJAwAAAA==.',
Ps='Pseudoholy:BAAALgADCgEJAQAAAA==.',
Pu='Putridvigor:BAACLgAFFH8FAAIdAAMJYxuUEQAAAQAdAAMJYxuUEQAAAQAuAAQKfxkAAx0ACQmCF80IADwCAB0ACQlmF80IADwCABwAAwmfBiTZAHsAAAAA.Puzzlewalrus:BAAALgADCgQJBAAAAA==.',
Py='Pyreiella:BAAALgADCgUJBQAAAA==.Pyroamor:BAAALgAECgEJAQAAAA==.Pyropete:BAABLgAECn8PAAMEAAcJngKHyAC5AAAEAAcJMgKHyAC5AAApAAQJcALNCQBsAAAAAA==.',
['Pä']='Pälii:BAABLgAECn8nAAMGAAkJdQfTKAB4AQAGAAkJdQfTKAB4AQAHAAQJhA4l4QDLAAAAAA==.',
Qc='Qcomberoo:BAAALgADCgMJAwAAAA==.',
Ra='Ragublaster:BAAALgAECgEJAQABLgAFFAUJEAASAAccAA==.Ragz:BAAALgAECgYJBgAAAA==.Ralickan:BAAALgADCgcJBQAAAA==.Ramaan:BAABLgAECn8YAAIZAAkJ0xr5CQDKAgAZAAkJ0xr5CQDKAgAAAA==.Ramble:BAAALgAECgcJDQAAAA==.Ravette:BAABLgAECn8wAAMmAAkJvSNIAgAEAwAmAAkJvSNIAgAEAwAgAAMJnBNWHgCVAAAAAA==.Ravissante:BAABLgAECn8eAAIiAAcJ2QbheQDYAAAiAAcJ2QbheQDYAAAAAA==.Rawranator:BAAALgAECgYJDgAAAA==.',
Re='Reesecupthis:BAABLgAECn8fAAILAAgJHCL9AwB7AgALAAgJHCL9AwB7AgABLgAFFAYJFQALAHcbAA==.Remagix:BAAALgAECgEJAQAAAA==.Revek:BAAALgADCgEJAQAAAA==.Reveurus:BAAALgADCgcJBwABLgAECgkJJAAGAGAjAA==.Rezzaleya:BAAALgADCgQJBAAAAA==.',
Rh='Rhaena:BAAALgAECgYJDQABLgAECgkJDgAbAAAAAA==.Rhonis:BAAALgAECgUJCwAAAA==.',
Ri='Riceroll:BAABLgAECn8bAAMOAAcJKyAKQgCXAQAOAAYJ6x4KQgCXAQAXAAQJIB0zJAA4AQAAAA==.Rickyspanish:BAAALgAECgcJBAAAAA==.Ricochet:BAABLgAECn8lAAIGAAgJIhHCJACUAQAGAAgJIhHCJACUAQAAAA==.Rioszen:BAAALgADCgIJAgAAAA==.Riseordie:BAAALgADCgYJCAAAAA==.',
Ro='Rollmybitzup:BAAALgAFFAEJAwABLgAFFAUJEAASAAccAA==.Ronnycoleman:BAAALgAECgMJAwAAAA==.Roofonfire:BAABLgAECn8bAAMVAAgJrwk0EgAZAQAVAAgJ6gg0EgAZAQAaAAMJvwYzdwBmAAAAAA==.Roreck:BAAALgAECgkJBAAAAA==.Rowyn:BAAALgADCgEJAQAAAA==.',
Ru='Runeka:BAACLgAFFH8GAAIRAAMJqyHRFgAsAQARAAMJqyHRFgAsAQAuAAQKfyMAAhEACAmaJXEHAMsCABEACAmaJXEHAMsCAAAA.Rusalkha:BAAALgADCgEJAQAAAA==.Ruteefear:BAAALgAECgUJDQAAAA==.',
Ry='Rybes:BAAALgAECgUJDAAAAA==.Rychesus:BAAALgADCgYJBgABLgAECgUJCQAbAAAAAA==.',
Sa='Safehaven:BAAALgAECgMJAwAAAA==.Saintcloud:BAAALgADCgkJEAAAAA==.Sairuwki:BAAALgAECgYJCQAAAA==.Samwìse:BAACLgAFFH8TAAINAAUJGA4BCgBKAQANAAUJGA4BCgBKAQAuAAQKfywAAw0ACAkzJHUOAHYCAA0ACAkzJHUOAHYCABgABAnJEoBJAIcAAAAA.Sareir:BAAALgADCgMJAwAAAA==.Sato:BAAALgAECgEJAQAAAA==.Savagex:BAAALgADCgYJBgAAAA==.Saveena:BAAALgAECgYJDgAAAA==.',
Sc='Scarlla:BAABLgAECn8XAAIZAAkJlh5wCQDRAgAZAAkJlh5wCQDRAgAAAA==.Scorber:BAAALgAECgIJAgAAAA==.',
Se='Searingbear:BAAALgADCgQJBAABLgAECgEJAQAbAAAAAA==.Senggolbacok:BAAALgAFFAIJAgAAAA==.Senpaii:BAAALgAECgEJAgAAAA==.Senseitheta:BAAALgAECgEJAgABLgAECggJGAAOAPIYAA==.Sepherios:BAAALgADCgYJBgAAAA==.Serengenuity:BAAALgAFFAEJAQAAAA==.Serenidin:BAAALgAECgEJAQAAAA==.Serenio:BAAALgAECgEJBAAAAA==.Sereniswift:BAAALgAECgQJBQAAAA==.Serephita:BAABLgAECn8uAAIEAAkJmwgYXwCBAQAEAAkJmwgYXwCBAQAAAA==.',
Sg='Sgtsnipe:BAAALgAECgQJBQAAAA==.',
Sh='Shakys:BAABLgAECn8bAAMEAAcJoBm0UACnAQAEAAcJoBm0UACnAQApAAEJqwi8DQAwAAAAAA==.Shalaylea:BAAALgAECgQJBgAAAA==.Shamwich:BAABLgAECn8YAAMaAAYJxQ3YPADoAAAaAAYJxQ3YPADoAAAZAAQJtAQldgCDAAAAAA==.Shanondorf:BAABLgAECn8bAAMUAAgJ3htvAwAYAgAUAAgJ5RpvAwAYAgAQAAUJdxoGJgAGAQAAAA==.Shark:BAABLgAECn8YAAMKAAYJ6RIWTgAPAQAKAAYJ6RIWTgAPAQABAAUJAgzhPwC2AAABLgAFFAUJFwAcAHASAA==.Shaymist:BAAALgAECgMJAwAAAA==.Sheeplord:BAAALgADCgQJBgAAAA==.Sheepstealer:BAABLgAECn8vAAMSAAkJ6BMfFwDSAQASAAkJ6BMfFwDSAQATAAQJLgJJNAByAAAAAA==.Shiggyll:BAAALgADCgIJAgAAAA==.Shildo:BAABLgAECn8tAAMYAAkJiBraCgBXAgAYAAkJiBraCgBXAgARAAEJQQutVAA4AAAAAA==.Shirokuma:BAAALgAECgMJAwAAAA==.Shiryunuri:BAAALgADCgUJCAAAAA==.Shizzo:BAAALgAECgYJEgAAAA==.Shockrock:BAAALgAECgQJBQAAAA==.Shybuzz:BAAALgAECgYJBgAAAA==.Shøstákovich:BAAALgADCgEJAQAAAA==.',
Si='Sifen:BAABLgAFFH8HAAIHAAUJaQ2jJwAzAQAHAAUJaQ2jJwAzAQAAAA==.Silecra:BAAALgADCgcJBwABLgAFFAMJBgARAKshAA==.Sinscale:BAAALgAECgQJBAABLgAFFAYJFgAHAFYdAA==.Sinswrath:BAACLgAFFH8WAAIHAAYJVh1MCAC1AQAHAAYJVh1MCAC1AQAuAAQKfyUAAgcACAkWJIQJAEUDAAcACAkWJIQJAEUDAAAA.',
Sk='Skarre:BAACLgAFFH8DAAIiAAIJyAmLWgCIAAAiAAIJyAmLWgCIAAAuAAQKfyEAAiIABwnbHDAwADoCACIABwnbHDAwADoCAAAA.Skcusnor:BAAALgAECgcJEQAAAA==.Skelevyrn:BAAALgADCgEJAQAAAA==.Skimnms:BAAALgADCgUJBgAAAA==.Skrimbly:BAAALgAECgEJAQAAAA==.',
Sl='Slaye:BAAALgAECgkJEwAAAA==.',
Sm='Smiteheal:BAAALgADCgMJAwAAAA==.Smores:BAACLgAFFH8OAAIKAAUJpx/GCQDOAQAKAAUJpx/GCQDOAQAuAAQKfyAAAgoACQkAJaYEAEQDAAoACQkAJaYEAEQDAAEuAAUUBwkfAAoADB8A.Smrts:BAAALgAECggJCwAAAA==.',
Sn='Snaccident:BAACLgAFFH8JAAMTAAMJdgiKBQC0AAATAAMJiAKKBQC0AAASAAMJIQgHOACKAAAuAAQKfycAAxIACQnBEQAhALgBABIACQnBEQAhALgBABMAAQnBAHJGABkAAAAA.Snaccidentsh:BAAALgADCgMJAgABLgAFFAMJCQATAHYIAA==.Snaccidentww:BAABLgAECn8UAAIJAAgJDwolKAAkAQAJAAgJDwolKAAkAQABLgAFFAMJCQATAHYIAA==.Sneakyteeth:BAABLgAECn8nAAIQAAgJABQdEgDDAQAQAAgJABQdEgDDAQAAAA==.Snotzz:BAAALgAECgUJBgAAAA==.',
So='Sojukai:BAAALgAECgEJAQAAAA==.Sok:BAAALgAECgUJDgAAAA==.Solonör:BAAALgADCgcJCAAAAA==.Songi:BAABLgAECn8fAAIcAAgJEiJ4KACZAgAcAAgJEiJ4KACZAgAAAA==.Soulwhisper:BAACLgAFFH8WAAIcAAYJSRlBFQCfAQAcAAYJSRlBFQCfAQAuAAQKfyUAAhwACAldI1IVAPwCABwACAldI1IVAPwCAAAA.',
Sp='Spaghetifire:BAABLgAFFH8QAAISAAUJBxw9EgBbAQASAAUJBxw9EgBbAQAAAA==.Sparklybeach:BAAALgADCggJCAAAAA==.Sphyr:BAABLgAECn8XAAMHAAgJ5gUqlQD+AAAHAAgJ1gQqlQD+AAALAAQJVQUQLABrAAAAAA==.Spicynoodi:BAABLgAECn8cAAMTAAgJhgfWHQA/AQATAAcJgwfWHQA/AQASAAMJ0gWyVwB2AAAAAA==.Spyrodruid:BAAALgAFFAEJAQABLgAFFAQJBQAPAMAQAA==.Spyromonk:BAABLgAFFH8FAAIPAAQJwBATGQAZAQAPAAQJwBATGQAZAQAAAA==.',
Sq='Sqoots:BAABLgAECn8hAAIEAAgJDiJ4IQDtAgAEAAgJDiJ4IQDtAgAAAA==.',
St='Stankyfist:BAAALgAECgUJCAAAAA==.Starfeish:BAAALgAECgcJEAAAAA==.Stepzlol:BAAALgADCgIJAwAAAA==.Stopresistin:BAAALgAECgUJCQAAAA==.Stormsinger:BAABLgAECn8pAAMaAAkJPxcPFAD3AQAaAAkJPxcPFAD3AQAZAAgJERGBTgBJAQAAAA==.',
Su='Succubis:BAAALgADCgIJAgAAAA==.Sugarblast:BAACLgAFFH8NAAMaAAUJIhyTCQBEAQAaAAQJIhyTCQBEAQAVAAEJAAC2DQAAAAAuAAQKfyMAAhoACAn6IwwLAOcCABoACAn6IwwLAOcCAAAA.Sukker:BAAALgAECgMJBAAAAA==.Sukkler:BAAALgADCgYJCAAAAA==.Sumtingwong:BAAALgADCgYJBgAAAA==.Suou:BAACLgAFFH8TAAMDAAUJyiAfCAB4AQADAAUJyiAfCAB4AQACAAEJlQmbCwBUAAAuAAQKfyEAAwMACQkLIdIhAEYCAAMABwk5IdIhAEYCAAIAAgmBIAAuAK4AAAAA.Supadoc:BAACLgAFFH8FAAIZAAMJJg7FMADBAAAZAAMJJg7FMADBAAAuAAQKfxYAAhkACQl3DsopALwBABkACQl3DsopALwBAAAA.Superchicken:BAAALgAECgIJAgAAAA==.Surfbird:BAAALgAECgYJBgAAAA==.',
Sv='Svekkê:BAAALgAECgcJBwAAAA==.',
Sw='Swagmeoutbro:BAAALgADCgIJAgAAAA==.',
Sy='Sylint:BAAALgAECgYJCQAAAA==.Sylliseas:BAAALgADCgYJBgAAAA==.Sylvara:BAAALgAECgUJBwAAAA==.Sylverhooves:BAAALgAECgMJAwAAAA==.Sylverlock:BAAALgAECgIJAgAAAA==.',
Ta='Ta:BAAALgADCgIJAgAAAA==.Tacosdk:BAAALgAECgUJCAAAAA==.Tacoss:BAAALgAECgIJAgAAAA==.Taladiira:BAAALgADCgcJAgAAAA==.Tandragosa:BAAALgAECgMJBAABLgAECgkJKQAaAD8XAA==.Tankadiin:BAAALgAECgQJBAAAAA==.Tannica:BAAALgADCgYJBgAAAA==.Tanthyr:BAAALgAECgYJBgAAAA==.Tayswiftagos:BAAALgAECgcJEAAAAA==.',
Te='Teddy:BAAALgADCgMJAwAAAA==.Teddyy:BAAALgAECgcJBwAAAA==.Texazmade:BAAALgAECgUJBgAAAA==.Textacô:BAAALgAECgUJBQABLgAECgUJBgAbAAAAAA==.',
Th='Thagomizer:BAAALgADCgIJAgAAAA==.Thechadlad:BAAALgADCgYJBgAAAA==.Thedevilssin:BAAALgAFFAMJAwAAAA==.Thefool:BAAALgADCgYJBgAAAA==.Theocles:BAAALgADCgYJDwAAAA==.Theodas:BAABLgAECn8UAAIcAAgJkhdoNADmAQAcAAgJkhdoNADmAQAAAA==.Therru:BAAALgADCggJGAABLgAECgcJFAARAEwMAA==.Thien:BAAALgADCgkJCQAAAA==.Thorimm:BAAALgAECgEJAQAAAA==.Throbbert:BAAALgADCgcJBwABLgAECggJGwAUAN4bAA==.Thunderwater:BAAALgAECgQJCAAAAA==.',
Ti='Tiken:BAAALgAECgEJAwAAAA==.Tiktok:BAAALgAECgUJEgABLgAECgcJEAAbAAAAAA==.Tippss:BAACLgAFFH8NAAINAAQJDCBiCABkAQANAAQJDCBiCABkAQAuAAQKfzYAAw0ACQm5JfgBAFQDAA0ACQm5JfgBAFQDABEACAmsFiQPACUCAAAA.Tipsygypsy:BAABLgAECn8oAAIEAAcJdAq/gAA5AQAEAAcJdAq/gAA5AQAAAA==.Tique:BAAALgAECgYJBgAAAA==.',
To='Tokenbeef:BAACLgAFFH8KAAIZAAMJxBOkKwDWAAAZAAMJxBOkKwDWAAAuAAQKfzAAAxkACAm5G5sSAGUCABkACAm5G5sSAGUCABoAAwlEBBJ2AGoAAAAA.Tokenshaman:BAABLgAECn8bAAIVAAYJfQwMFwBQAQAVAAYJfQwMFwBQAQAAAA==.Torlon:BAAALgADCgEJAQAAAA==.Toxicdk:BAAALgAFFAIJAwABLgAFFAIJBgAVAF8PAA==.Toxicshamy:BAACLgAFFH8GAAMVAAIJXw9OCQCYAAAVAAIJAA9OCQCYAAAaAAIJKgSbGQCIAAAuAAQKfyAABBUACQk7FxoHAP8BABUACAmfGRoHAP8BABoABwnQEycpAMsBABkAAQm1GIePAEQAAAAA.',
Tr='Trafficcones:BAAALgAECgMJAwAAAA==.Traugdor:BAAALgADCgkJDgAAAA==.Traylay:BAACLgAFFH8RAAIHAAUJlxzsFgBhAQAHAAUJlxzsFgBhAQAuAAQKfyEAAgcACQnZJKEMACkDAAcACQnZJKEMACkDAAAA.Traylei:BAAALgADCgcJBwABLgAFFAUJEQAHAJccAA==.Tremana:BAAALgAECgMJAwAAAA==.Trio:BAAALgADCgUJBQAAAA==.Trixaintime:BAABLgAECn8WAAIHAAYJUQlzqwArAQAHAAYJUQlzqwArAQAAAA==.',
Ts='Tsm:BAAALgADCgYJBgAAAA==.',
Tt='Ttocs:BAACLgAFFH8RAAIaAAQJTRaQEgAvAQAaAAQJTRaQEgAvAQAuAAQKfyoAAhoACQnVIs8GACYDABoACQnVIs8GACYDAAEuAAUUBQkHAAcAaQ0A.',
Tu='Tujori:BAACLgAFFH8LAAMRAAUJiA72DgDgAAARAAQJMBH2DgDgAAANAAEJ6ANyIgBLAAAuAAQKfx4AAw0ACAmeEp0uAIkBAA0ACAlJC50uAIkBABEABwm+ErclAGcBAAAA.Turuce:BAAALgADCgYJBgAAAA==.',
Tv='Tv:BAAALgADCgcJBwABLgAECgMJAwAbAAAAAA==.',
Tw='Twherk:BAAALgAECgcJEQABLgAFFAYJDwARAPsQAA==.Twinmoonfury:BAABLgAECn88AAMBAAkJ/RtJCACIAgABAAkJ/RtJCACIAgAKAAYJPBO8WgBCAQAAAA==.Twobit:BAAALgAECgYJBgAAAA==.',
Ty='Tylann:BAAALgADCgIJAgAAAA==.Tynestra:BAABLgAECn8dAAIiAAgJeBVbNACqAQAiAAgJeBVbNACqAQAAAA==.',
['Tí']='Tíger:BAAALgADCgQJAwAAAA==.',
['Tü']='Tüyria:BAAALgADCgMJAwAAAA==.',
Ug='Uglydorf:BAABLgAECn8jAAIjAAkJfBqRFABkAgAjAAkJfBqRFABkAgAAAA==.',
Uh='Uhh:BAAALgADCgcJCQAAAA==.',
Ul='Ulraka:BAAALgADCgEJAQAAAA==.Ultraviolenc:BAAALgAECgEJAQAAAA==.',
Un='Unholydiver:BAAALgADCgEJAQAAAA==.',
Va='Vaeros:BAABLgAECn8dAAISAAgJ4g8nJABoAQASAAgJ4g8nJABoAQAAAA==.Valantis:BAEALgAECgQJBQAAAA==.Valcantor:BAAALgAECgYJDAAAAA==.Vanyss:BAAALgADCgYJBgAAAA==.',
Ve='Vekz:BAABLgAECn8kAAIGAAkJTx7LEwB0AgAGAAkJTx7LEwB0AgAAAA==.Velazq:BAAALgADCgEJAgAAAA==.Velicia:BAABLgAECn8hAAICAAgJnxoICgD2AQACAAgJnxoICgD2AQAAAA==.Velithice:BAAALgAECgYJBwAAAA==.Venture:BAAALgAECgQJBAAAAA==.',
Vo='Voidnjoyr:BAAALgAECgEJAQAAAA==.',
Wa='Walsun:BAAALgADCgcJDQABLgAECgkJKQAaAD8XAA==.Warheadx:BAAALgAECgQJBAAAAA==.Warhéad:BAAALgAECgUJDwAAAA==.Wartonxp:BAABLgAECn8sAAIYAAgJgB5ADgCfAgAYAAgJgB5ADgCfAgAAAA==.Waterbôy:BAACLgAFFH8OAAIaAAQJchjbDwBBAQAaAAQJchjbDwBBAQAuAAQKfzYABBoACQnVIXYGALkCABoACQnVIXYGALkCABkABQliCZdnAPAAABUAAgktBQgoAFwAAAAA.Waynee:BAAALgAECgcJDAAAAA==.',
We='Weepylight:BAAALgAECgMJAwAAAA==.Weissbrew:BAAALgADCgUJBQAAAA==.',
Wh='Wheezy:BAAALgAFFAIJAgAAAA==.Whoasked:BAACLgAFFH8KAAISAAQJ1hS/GAAwAQASAAQJ1hS/GAAwAQAuAAQKfzcAAxIACQkuJSMCAD4DABIACQkuJSMCAD4DABMABglJFyscAE8BAAAA.',
Wi='Wiggle:BAABLgAECn8zAAIFAAkJcyBeAAABAwAFAAkJcyBeAAABAwAAAA==.Wildslayer:BAAALgADCgUJBQAAAA==.',
Wo='Wolf:BAAALgAECgEJAQAAAA==.',
Wt='Wtfheal:BAACLgAFFH8PAAIRAAYJ+xBmDwCGAQARAAYJ+xBmDwCGAQAuAAQKfyUAAhEACAkaI7QFAPMCABEACAkaI7QFAPMCAAAA.',
Xa='Xanistra:BAACLgAFFH8RAAIOAAUJ2BeYLQA1AQAOAAUJ2BeYLQA1AQAuAAQKfyUAAw4ACQkqH0oNABADAA4ACQkqH0oNABADABcABAm/HFUtAAgBAAAA.Xaylor:BAAALgADCgcJCgAAAA==.',
Xg='Xgamesmode:BAAALgADCgEJAgABLgAFFAMJCAAJANQbAA==.',
Xz='Xzlemina:BAAALgAECgcJCQAAAA==.',
Ya='Yalaforth:BAABLgAECn8mAAIHAAkJHxMINgDhAQAHAAkJHxMINgDhAQAAAA==.Yamashaman:BAABLgAECn81AAMZAAkJVCCLBQASAwAZAAkJVCCLBQASAwAaAAEJxgfCfwAoAAAAAA==.Yardgnome:BAAALgAFFAIJAgAAAA==.',
Ye='Yebefd:BAAALgADCgcJBwAAAA==.',
Yu='Yungbluudd:BAAALgAFFAIJAgAAAA==.',
Za='Zaleth:BAAALgAECgQJBQAAAA==.Zaliel:BAAALgAECgEJAgAAAA==.Zamasu:BAABLgAECn8gAAIiAAgJJyHXDwCEAgAiAAgJJyHXDwCEAgAAAA==.Zapmybitzup:BAAALgAFFAMJBAABLgAFFAUJEAASAAccAA==.Zaroneus:BAAALgADCgUJBQAAAA==.Zaszadin:BAECLgAFFH8WAAIHAAUJwiWGBwC+AQAHAAUJwiWGBwC+AQAuAAQKfycAAgcACQldI+sZAM0CAAcACQldI+sZAM0CAAAA.Zaszhadoom:BAEALgAECgMJAwABLgAFFAUJFgAHAMIlAA==.Zaxxon:BAABLgAECn8rAAMSAAkJLRvGCgBpAgASAAkJLRvGCgBpAgATAAEJDQ3LPgA0AAAAAA==.',
Ze='Zekt:BAAALgADCgQJBAAAAA==.Zelo:BAAALgAECgYJCwAAAA==.Zensi:BAAALgAECgEJAQAAAA==.Zerax:BAABLgAECn8yAAIfAAkJcxokBgBkAgAfAAkJcxokBgBkAgAAAA==.',
Zi='Zigfury:BAAALgAECgYJDwAAAA==.Zillagoth:BAAALgAECgMJAgAAAA==.Zira:BAABLgAECn8qAAIIAAgJEBPMHgCkAQAIAAgJEBPMHgCkAQAAAA==.',
Zo='Zombiebrainz:BAAALgAECgUJCQAAAA==.Zombiebubble:BAAALgAECgkJDQAAAA==.Zoìdberg:BAACLgAFFH8PAAIZAAIJ3xyYFwCdAAAZAAIJ3xyYFwCdAAAuAAQKfzYAAhkACAkEIrMHAPoCABkACAkEIrMHAPoCAAAA.',
Zs='Zselk:BAAALgADCgYJCAAAAA==.',
Zu='Zubzer:BAABLgAECn8dAAIcAAkJsBkgIQA+AgAcAAkJsBkgIQA+AgAAAA==.',
Zz='Zzor:BAACLgAFFH8aAAIEAAUJsR4tIwB0AQAEAAUJsR4tIwB0AQAuAAQKfyUAAgQACQknJREPAE8DAAQACQknJREPAE8DAAAA.Zzorfel:BAAALgAECgEJAgABLgAFFAUJGgAEALEeAA==.Zzorshock:BAAALgAECgYJDAABLgAFFAUJGgAEALEeAA==.',
['Ði']='Ðii:BAAALgAECgMJAwAAAA==.',
['ßl']='ßlue:BAABLgAECn8iAAIEAAgJUBMoUQCmAQAEAAgJUBMoUQCmAQABLgAFFAQJBQAPAB8QAA==.',
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
