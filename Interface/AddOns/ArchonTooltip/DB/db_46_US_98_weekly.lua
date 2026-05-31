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

local lookup = {'Druid-Balance','Warrior-Arms','Warrior-Fury','Mage-Frost','Mage-Arcane','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Druid-Restoration','Monk-Mistweaver','Monk-Windwalker','Warrior-Protection','Hunter-Survival','Priest-Discipline','Warlock-Demonology','Monk-Brewmaster','Rogue-Subtlety','Evoker-Augmentation','Evoker-Devastation','Rogue-Outlaw','Shaman-Enhancement','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Preservation','DemonHunter-Vengeance','Rogue-Assassination','DemonHunter-Devourer','Hunter-BeastMastery','Druid-Feral','DeathKnight-Frost','Paladin-Protection','Priest-Holy','DemonHunter-Havoc','Hunter-Marksmanship','Druid-Guardian','Mage-Fire',}
local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Aberdus:BAABLgAECn8YAAIBAAcJJRVgLwBHAQABAAcJJRVgLwBHAQAAAA==.',
Ac='Accalon:BAABLgAECn8pAAMCAAgJqRraEgC0AQADAAgJLRfsGwD7AQACAAgJGBjaEgC0AQABLgAECggJJQAEACkZAA==.',
Ad='Adina:BAAALgAECgYJBgAAAA==.Advacus:BAACLgAFFH8WAAMEAAYJhxbrKgCPAQAEAAYJGhTrKgCPAQAFAAIJ6hW5AwBVAAAuAAQKfyUAAwUACAlmH/8BAJACAAUACAmWGv8BAJACAAQACAkEHEZQAEYCAAAA.',
Ai='Aicila:BAAALgADCgEJAQAAAA==.Aimer:BAAALgAECgEJAQAAAA==.Airi:BAAALgADCgYJCAABLgAFFAEJAQAGAAAAAA==.',
Ak='Akrama:BAABLgAECn8tAAMHAAkJuRzEFwA0AgAHAAkJuRzEFwA0AgAIAAYJdAnT0gDQAAAAAA==.',
Al='Alara:BAAALgADCgkJEwAAAA==.Alatáriel:BAAALgAECgIJAgAAAA==.Alectrona:BAAALgAECgQJBwAAAA==.Aletriss:BAABLgAECn8ZAAMJAAYJVAvXYwD4AAAJAAYJVAvXYwD4AAABAAYJnAZ7UACvAAAAAA==.Alexsham:BAAALgAECgEJAQAAAA==.Algaraz:BAAALgAECgYJDgAAAA==.',
Am='Ama:BAAALgAECgQJBQAAAA==.Amnorpse:BAABLgAECn8oAAIDAAgJBSDLDQB/AgADAAgJBSDLDQB/AgAAAA==.',
An='Anabana:BAAALgAECgYJEAAAAA==.Angler:BAABLgAECn8iAAMKAAkJCBqeDQCiAgAKAAkJCBqeDQCiAgALAAEJrAUEogAkAAAAAA==.Anruu:BAAALgAECgUJBQAAAA==.Anthraxass:BAAALgAECgkJCQAAAA==.',
Ap='Appollis:BAAALgAECgEJAQAAAA==.Appropriate:BAAALgADCgMJAwAAAA==.',
Ar='Araleth:BAAALgAECgMJAwAAAA==.Arkthurus:BAAALgAECgYJDgAAAA==.Artumis:BAAALgADCgEJAQAAAA==.Arvitherejet:BAAALgAECgYJDgAAAA==.',
As='Aschern:BAAALgAECgYJDAAAAA==.Ashenfang:BAAALgAECgQJBAAAAA==.Ashijin:BAACLgAFFH8UAAIIAAUJdhqWKwA/AQAIAAUJdhqWKwA/AQAuAAQKfycAAggACQlVIREmAI4CAAgACQlVIREmAI4CAAAA.Ashilyn:BAAALgAECgEJAQAAAA==.Ashoo:BAAALgADCgEJAQAAAA==.Astei:BAAALgADCgEJAQAAAA==.',
At='Ataxxius:BAAALgADCgMJAwAAAA==.Atheristina:BAAALgAECgQJDAABLgAECggJHQAJADgcAA==.Atroce:BAAALgAECgYJDQAAAA==.Atticu:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAABLgAECn8/AAIHAAkJPRmtEwBdAgAHAAkJPRmtEwBdAgAAAA==.Auxilium:BAABLgAECn8cAAIIAAkJohXRSAAIAgAIAAkJohXRSAAIAgAAAA==.',
Aw='Awnen:BAABLgAECn8dAAIMAAYJjwvpKwDAAAAMAAYJjwvpKwDAAAAAAA==.',
Az='Aza:BAAALgADCgIJAgAAAA==.',
Ba='Backtrakk:BAAALgADCgMJAwAAAA==.Baelsson:BAAALgAECgkJCAAAAA==.Bahndis:BAAALgADCgcJDAAAAA==.Balebrew:BAAALgAFFAIJAgAAAA==.Balethar:BAAALgAFFAEJAQABLgAFFAIJAgAGAAAAAA==.Ballador:BAAALgAECggJEQAAAA==.Balluh:BAABLgAECn89AAINAAgJpxl1EQATAgANAAgJpxl1EQATAgAAAA==.',
Be='Bearforceone:BAAALgAECgEJAQAAAA==.Beartest:BAAALgAECgMJBAABLgAFFAYJDAAOAEwJAA==.Beezen:BAACLgAFFH8UAAILAAcJYxYmBAC6AQALAAcJYxYmBAC6AQAuAAQKfyUAAgsACAm/IUcFADADAAsACAm/IUcFADADAAAA.Belara:BAAALgADCgYJBwAAAA==.Bellevo:BAAALgAECgQJBAABLgAECgkJKQAEAFMfAA==.Bellmage:BAABLgAECn8pAAMEAAkJUx8VGQCtAgAEAAkJUx8VGQCtAgAFAAEJxAlqHwAxAAAAAA==.Belttoash:BAABLgAECn8zAAIIAAcJox3ZSADUAQAIAAcJox3ZSADUAQAAAA==.Beneficiary:BAAALgAECgQJBQAAAA==.Bercey:BAABLgAECn8eAAIPAAkJwA7cSQCxAQAPAAkJwA7cSQCxAQAAAA==.Beybladetest:BAACLgAFFH8GAAMLAAMJRw2XIwCoAAALAAMJxQiXIwCoAAAQAAIJkw+LGwCQAAAuAAQKfyAABBAACQkVGgEWAFoCABAACAnmGgEWAFoCAAsABAmSGUVBAOEAAAoABAlQCnlwAI0AAAEuAAUUBgkMAA4ATAkA.',
Bi='Bigmang:BAAALgADCgYJBgAAAA==.Bigmayex:BAAALgADCgkJFgABLgAECgkJGgARAMsaAA==.Bigscott:BAAALgAECgMJAwABLgAFFAUJDAAIAIkXAA==.Bilmuri:BAAALgAECgUJCAAAAA==.Binky:BAAALgADCgIJAgAAAA==.',
Bl='Blackbride:BAAALgAECgUJBwAAAA==.Blackfyre:BAAALgAECgIJBAAAAA==.Blackmage:BAAALgAFFAEJAQAAAA==.Blastknight:BAAALgAECgIJAgABLgAFFAUJEgADAGsfAA==.Blizzdrood:BAAALgAECggJEwABLgAECgkJPAAPAJ4XAA==.Blizzlock:BAABLgAECn88AAIPAAkJnhefIgBKAgAPAAkJnhefIgBKAgAAAA==.Blood:BAAALgAECgIJBAAAAA==.Bloodfeast:BAAALgADCgYJBgAAAA==.Blooms:BAAALgADCgIJAgAAAA==.Blurednuhtz:BAAALgADCgYJCQAAAA==.',
Bo='Bobcatross:BAAALgADCgYJBgAAAA==.Bohvicce:BAAALgADCgEJAQAAAA==.Bokudo:BAAALgADCgMJAwAAAA==.Bonezs:BAABLgAECn9NAAMJAAkJFiMxBQBZAwAJAAkJFiMxBQBZAwABAAUJvhOLRADdAAAAAA==.Bonkus:BAAALgAECgQJBAAAAA==.Boogiepop:BAAALgAECgcJEwAAAA==.Bootylika:BAABLgAECn8bAAIDAAgJkxWiLgD3AQADAAgJkxWiLgD3AQAAAA==.Borislav:BAAALgADCgEJAQAAAA==.Bossvega:BAAALgAECgYJEQAAAA==.Boutdatbass:BAABLgAECn8ZAAIMAAYJ1wgOLQC5AAAMAAYJ1wgOLQC5AAAAAA==.',
Br='Braxxar:BAABLgAECn8ZAAIIAAgJuwyPgQBRAQAIAAgJuwyPgQBRAQAAAA==.Brendelf:BAAALgADCgcJCQAAAA==.Brett:BAAALgAECgEJAgAAAA==.Briellia:BAAALgAECgYJDgAAAA==.Brightaf:BAAALgADCgkJDQAAAA==.Bruggerlock:BAEALgADCgMJAwAAAA==.Bruhkakke:BAAALgAECgcJBgABLgAFFAcJEQAOACYSAA==.Bryagh:BAABLgAECn8rAAMSAAkJnhV+FwACAgASAAkJnhV+FwACAgATAAIJnwwiNwBfAAAAAA==.',
Bu='Bubbam:BAAALgADCgYJCAAAAA==.Bufferbug:BAAALgADCgkJFAAAAA==.Bugbear:BAAALgAECggJEwAAAA==.Bulge:BAAALgADCgUJBQABLgAECggJGwAUAN8bAA==.Bullithead:BAAALgAECgQJBAAAAA==.Bullycow:BAABLgAECn8XAAIVAAYJJgXhGgAbAQAVAAYJJgXhGgAbAQAAAA==.Bushybrowsy:BAABLgAECn8zAAQWAAkJLBMaBwDiAQAWAAkJLBMaBwDiAQAPAAcJSwgXlAAKAQAXAAMJRwJ5XQBWAAAAAA==.Buttercupz:BAABLgAECn8dAAIYAAkJlgtpKQBlAQAYAAkJlgtpKQBlAQAAAA==.',
['Bá']='Bámboo:BAAALgAECgEJAQAAAA==.',
['Bî']='Bîgdaddy:BAABLgAECn8rAAMZAAkJCBdAGwBXAgAZAAkJCBdAGwBXAgAaAAQJmgNqagCaAAAAAA==.',
Ca='Cacho:BAAALgAECggJCgAAAA==.Calevan:BAAALgAECgkJDwAAAA==.Candoran:BAAALgADCgMJAwAAAA==.Caracarn:BAAALgAECgcJDAAAAA==.Carpulations:BAABLgAECn8XAAIPAAYJEBivhABQAQAPAAYJEBivhABQAQAAAA==.Catty:BAAALgAECgMJAwAAAA==.',
Cc='Ccyll:BAAALgADCgkJEgAAAA==.',
Ce='Celadonia:BAAALgAECgEJAQAAAA==.Cerofewol:BAAALgADCgMJAwABLgAECgUJBwAGAAAAAA==.Cerokos:BAAALgADCgUJBQAAAA==.Cerridwen:BAABLgAECn8aAAIOAAYJ6AloOwD5AAAOAAYJ6AloOwD5AAAAAA==.',
Ch='Chantini:BAAALgAECgUJBQAAAA==.Chartreuze:BAAALgAECgUJCgAAAA==.Chazmonk:BAAALgAECgEJAQABLgAFFAMJCwAZACQOAA==.Chazpriest:BAAALgAECgYJBgABLgAFFAMJCwAZACQOAA==.Chazzie:BAACLgAFFH8LAAIZAAMJJA7/RgCzAAAZAAMJJA7/RgCzAAAuAAQKfxwAAhkACQn8HEAKAPsCABkACQn8HEAKAPsCAAAA.Cheonsul:BAAALgADCgQJBgAAAA==.Chexmix:BAAALgAECgUJBQAAAA==.Chia:BAACLgAFFH8YAAMbAAYJURQWMAB4AQAbAAUJURQWMAB4AQAcAAEJAADYVwAAAAAuAAQKfyQAAhsACAlXHyM1ABYCABsACAlXHyM1ABYCAAAA.Chikn:BAABLgAECn8XAAIKAAgJ8xRYGAD7AQAKAAgJ8xRYGAD7AQAAAA==.Chirichiri:BAAALgADCgIJBAAAAA==.Chizu:BAAALgADCgUJBQABLgAFFAYJHgADADgeAA==.Chomboslice:BAABLgAECn8oAAMHAAkJXBxfEgB/AgAHAAkJXBxfEgB/AgAIAAYJFREnpgASAQAAAA==.',
Cl='Clary:BAAALgAECgEJAQABLgAECggJIAAQALIZAA==.Classy:BAAALgAECgYJBwAAAA==.',
Cm='Cmil:BAACLgAFFH8VAAMHAAYJzxJvDwCjAQAHAAYJzxJvDwCjAQAIAAIJyAHSjQBjAAAuAAQKfyQAAwcACAnOEUsqAKYBAAcACAnOEUsqAKYBAAgAAQnODcpCATMAAAAA.',
Co='Coffeebrew:BAAALgAECgcJDwAAAA==.Coffeecrem:BAAALgAECgcJDQABLgAECgcJDwAGAAAAAA==.Coffeelune:BAAALgAECgIJAwAAAA==.Coffie:BAAALgADCgUJBQABLgAECgcJDwAGAAAAAA==.Coldnoodles:BAAALgAECgMJAwABLgAFFAMJCgALAJUZAA==.Combat:BAACLgAFFH8RAAIDAAUJARhqCwBKAQADAAUJARhqCwBKAQAuAAQKfx4AAgMACAk/HkoVAKMCAAMACAk/HkoVAKMCAAAA.Cornish:BAECLgAFFH8cAAIKAAYJFCKgBwBCAgAKAAYJFCKgBwBCAgAuAAQKfzUAAwoACQkDJCMCAJ0DAAoACQkDJCMCAJ0DAAsABQlPGdc2AA8BAAAA.Cornishpaste:BAEALgAECgQJBAABLgAFFAYJHAAKABQiAA==.Cosmo:BAAALgADCgcJCQABLgAECgkJFQALAC8YAA==.',
Cr='Crackjaw:BAAALgAECgMJBgAAAA==.Crakmybitzup:BAAALgAECgUJBQAAAA==.Crockodk:BAAALgAECgEJAQAAAA==.',
Cu='Curserodlock:BAAALgAECgcJDwAAAA==.',
Cy='Cyanide:BAAALgAECgYJBwAAAA==.',
Da='Dabbinshamin:BAABLgAECn8ZAAIZAAkJzBMLJwAKAgAZAAkJzBMLJwAKAgAAAA==.Dadanbing:BAAALgAECgYJBgABLgAFFAMJDQAZAJsWAA==.Daddyomg:BAAALgAECgYJCAABLgAFFAgJJgAaAAAdAA==.Dads:BAACLgAFFH8mAAMaAAgJAB2OBgALAgAaAAcJgRuOBgALAgAZAAQJKQhRRgC1AAAuAAQKfxsAAxoACQkWJSMQAKgCABoABwm6JCMQAKgCABkACQloF74iAA4CAAAA.Daggertest:BAAALgADCgQJBAABLgAFFAYJDAAOAEwJAA==.Dahai:BAAALgAECgMJAwAAAA==.Dakeyras:BAABLgAECn8iAAMMAAkJBBv1CABTAgAMAAkJBBv1CABTAgADAAMJIARFlQAyAAAAAA==.Danzon:BAAALgAECgEJAQAAAA==.Darcevoker:BAACLgAFFH8PAAIdAAYJ1AfBFAApAQAdAAYJ1AfBFAApAQAuAAQKfyYAAh0ACAk0GuoNAFkCAB0ACAk0GuoNAFkCAAAA.Darcmonk:BAABLgAFFH8FAAIKAAQJgwQdLQC9AAAKAAQJgwQdLQC9AAABLgAFFAYJDwAdANQHAA==.Darcpaladin:BAAALgAECgQJBQABLgAFFAYJDwAdANQHAA==.Darcshaman:BAAALgAECgIJAgABLgAFFAYJDwAdANQHAA==.Darkrune:BAABLgAECn8ZAAIbAAYJuhpRdQBkAQAbAAYJuhpRdQBkAQAAAA==.Darkschneide:BAAALgAECgQJBQAAAA==.Darthboo:BAAALgADCggJDAAAAA==.Darthtemplar:BAAALgAECgQJBAAAAA==.Darvolo:BAAALgADCgEJAQAAAA==.Davris:BAAALgAECgUJCQAAAA==.',
Db='Dbmagic:BAAALgAECggJEQAAAA==.',
De='Dealsun:BAABLgAECn8bAAMPAAgJdBObRAD+AQAPAAgJdBObRAD+AQAXAAUJ2QdIOADTAAAAAA==.Decynth:BAAALgAECgcJCQAAAA==.Defne:BAAALgAECgEJBQAAAA==.Demodorn:BAECLgAFFH8eAAIeAAYJIgZLBQDvAAAeAAYJIgZLBQDvAAAuAAQKfy0AAh4ACAm1Fk4IAPgBAB4ACAm1Fk4IAPgBAAAA.Demondudez:BAAALgAECgUJCwAAAA==.Demonikat:BAAALgADCgEJAQAAAA==.Demonsurfin:BAAALgAECgUJBQAAAA==.Demussi:BAAALgAECgEJAQAAAA==.Demyst:BAACLgAFFH8cAAMZAAYJJBTHDgC/AQAZAAYJJBTHDgC/AQAaAAUJlRDHIAABAQAuAAQKfyEAAxoACQlZHykSAJICABoACQlZHykSAJICABkAAgmmDd67ADgAAAAA.Deria:BAAALgAECgEJAQAAAA==.Devilsparda:BAAALgAECgMJAwAAAA==.Deweey:BAAALgAECggJEgAAAA==.Dezeraz:BAECLgAFFH8MAAIdAAQJbBwYBwB+AQAdAAQJbBwYBwB+AQAuAAQKfyMAAh0ACAkDJv4BAFsDAB0ACAkDJv4BAFsDAAEuAAUUBgkcAAoAFCIA.',
Dh='Dhecaye:BAAALgAECgEJAQABLgAFFAQJBgAKAPoKAA==.',
Di='Dieuscum:BAAALgAECgUJBgAAAA==.Diksneeze:BAAALgADCgUJCAAAAA==.Dince:BAAALgAECgEJAQAAAA==.Disengage:BAAALgAECgkJAwABLgAFFAUJEQADAAEYAA==.Dislogic:BAABLgAECn8kAAMPAAkJciLKDgDJAgAPAAgJciLKDgDJAgAXAAQJTSCiGwBwAQAAAA==.',
Dl='Dlorpglorp:BAAALgAECgIJAgABLgAECggJIQAEALgfAA==.',
Do='Dobbie:BAAALgADCgUJBQAAAA==.Donkey:BAAALgAECgcJCgAAAA==.Donmega:BAAALgAECgQJBwAAAA==.Doraleous:BAABLgAECn8tAAIHAAkJuR0iCwDGAgAHAAkJuR0iCwDGAgAAAA==.Dotzmybitzup:BAACLgAFFH8TAAMPAAQJmx5sLgBhAQAPAAQJmx5sLgBhAQAXAAEJRQ2eIgBGAAAuAAQKfzYABA8ACAmQJcUNANICAA8ACAmQJcUNANICABYAAglqEzEdAIgAABcAAQlXDm9jAEgAAAEuAAUUBgkTABIAohkA.Dougalleone:BAACLgAFFH8bAAIRAAYJCCATCQC/AQARAAYJCCATCQC/AQAuAAQKfyUAAxEACQmJIocHABgDABEACQmJIocHABgDAB8AAQmtEfsdAD0AAAAA.',
Dr='Draci:BAAALgADCgEJAQAAAA==.Drdumbottles:BAAALgAECgYJBgAAAA==.Dreadknott:BAACLgAFFH8KAAIbAAMJFxDnkwDFAAAbAAMJFxDnkwDFAAAuAAQKfzIAAhsACQleHRonAFICABsACQleHRonAFICAAAA.Dreadxknight:BAAALgADCgMJAwAAAA==.Drekim:BAABLgAECn8UAAISAAUJryAbLgBRAQASAAUJryAbLgBRAQAAAA==.Dreko:BAAALgAECgQJBgAAAA==.Drezzakmage:BAACLgAFFH8KAAIEAAQJMwh2XwARAQAEAAQJMwh2XwARAQAuAAQKfyIAAgQACQlcFl9gABoCAAQACQlcFl9gABoCAAEuAAUUBQkGAA0ANAoA.Drezzakzdh:BAAALgADCgYJBgABLgAFFAUJBgANADQKAA==.Druidiac:BAAALgADCgYJEwABLgAECgkJLQAYAIYaAA==.',
Du='Dugren:BAAALgAECgkJCQAAAA==.',
Ec='Echo:BAAALgADCgkJFQAAAA==.',
Ed='Edgelf:BAAALgADCgMJAwAAAA==.',
El='Elaidare:BAAALgAFFAMJBAAAAA==.Elaidine:BAABLgAECn8cAAMeAAkJEw1zDQBiAQAeAAkJEw1zDQBiAQAgAAEJAACwKQEAAAABLgAFFAMJBAAGAAAAAA==.Electraknub:BAAALgAECgQJBAAAAA==.Elisabetta:BAAALgADCgMJAwAAAA==.Elizalex:BAAALgAECgIJBAAAAA==.',
Em='Emagdne:BAAALgADCgMJAgAAAA==.Empath:BAAALgADCgQJBQAAAA==.',
En='Enferno:BAAALgAECgYJDgABLgAECgkJPAAPAJ4XAA==.Enfernum:BAAALgADCgEJAQABLgAECgkJPAAPAJ4XAA==.Engara:BAAALgAECgEJAgAAAA==.Enolad:BAAALgADCgcJBwABLgAECgcJDAAGAAAAAA==.Entrapy:BAAALgAECgEJAQAAAA==.',
Er='Eradius:BAAALgAECgYJCwAAAA==.Errai:BAABLgAECn80AAIPAAkJOSGWEAC7AgAPAAkJOSGWEAC7AgAAAA==.',
Es='Estefania:BAAALgAECgEJAQAAAA==.',
Eu='Eureka:BAABLgAECn8gAAIBAAkJ/xkLDQByAgABAAkJ/xkLDQByAgAAAA==.',
Ev='Evilnapkin:BAAALgAECgQJEQAAAA==.Evion:BAABLgAECn8gAAIhAAkJchvVHwBSAgAhAAkJchvVHwBSAgAAAA==.',
Ey='Eyedoll:BAAALgAECgEJAQAAAA==.Eyez:BAAALgADCgIJAgAAAA==.',
Fa='Faelthorn:BAAALgADCgQJBAAAAA==.Faemalis:BAAALgAECgEJAQAAAA==.Farseer:BAAALgADCgMJAwAAAA==.',
Fe='Feardoctor:BAAALgAECgUJCQAAAA==.Feelthepower:BAABLgAECn8WAAIEAAYJ2xh1lQAzAQAEAAYJ2xh1lQAzAQAAAA==.',
Fl='Flavorfrenzy:BAAALgADCgUJBQABLgAECgkJRAAcAPEkAA==.',
Fo='Fourimborniy:BAAALgAECgcJCwAAAA==.',
Fr='Frenzi:BAAALgADCgEJAQAAAA==.Friendulum:BAAALgAECgcJBwAAAA==.Fries:BAEALgAECgEJAQABLgAFFAQJBwAPAKYPAA==.Frostey:BAAALgADCgEJAQAAAA==.',
Fu='Fuzzsicle:BAAALgAECgYJCQAAAA==.Fuzzydìcê:BAAALgAECgUJCAAAAA==.',
['Fá']='Fáelen:BAABLgAECn8fAAIiAAgJOB6pBgCLAgAiAAgJOB6pBgCLAgAAAA==.',
Ga='Galang:BAAALgAECgMJBQAAAA==.Gangactivity:BAAALgAECgQJCwABLgAFFAMJCgALAB8fAA==.Garm:BAAALgAECgEJBAAAAA==.Garrt:BAABLgAECn8aAAIiAAcJdxqiDADLAQAiAAcJdxqiDADLAQAAAA==.Gartalvanise:BAAALgAECgkJDwAAAA==.Gartarrior:BAAALgADCgYJBgAAAA==.Gartt:BAAALgADCgEJAQAAAA==.Gavinrad:BAAALgAECggJEwAAAA==.',
Ge='Gelato:BAAALgADCgEJAgAAAA==.Genjee:BAAALgAECgMJAwAAAA==.Gep:BAACLgAFFH8FAAIIAAIJsiDGZQDAAAAIAAIJsiDGZQDAAAAuAAQKfxYAAggABwk1I1YpAEQCAAgABwk1I1YpAEQCAAAA.',
Gi='Gilene:BAAALgADCggJAwAAAA==.',
Gl='Glaalinix:BAAALgADCgkJGgAAAA==.Glaciiel:BAAALgAECgMJAwAAAA==.Globbie:BAAALgADCgMJAwAAAA==.',
Go='Goku:BAAALgAECgcJEAAAAA==.Goobman:BAAALgADCgQJBQABLgAFFAUJDwAJAGIaAA==.Goodman:BAABLgAECn8tAAIIAAkJ+R3VHgB3AgAIAAkJ+R3VHgB3AgAAAA==.Goomei:BAACLgAFFH8XAAILAAUJbRwhBAC6AQALAAUJbRwhBAC6AQAuAAQKfzIAAgsACQmnInEEAAADAAsACQmnInEEAAADAAEuAAUUCAkiACAAHBsA.Goomi:BAACLgAFFH8iAAIgAAgJHBuIBQB4AgAgAAgJHBuIBQB4AgAuAAQKfyMAAiAACQmWIxADAJ4DACAACQmWIxADAJ4DAAAA.Gordius:BAAALgADCgEJAQAAAA==.Gorok:BAAALgAECgUJDwAAAA==.Goybeam:BAAALgADCgcJCQAAAA==.',
Gr='Gravykin:BAABLgAECn8WAAIiAAkJcQ0aEQCCAQAiAAkJcQ0aEQCCAQAAAA==.Grayfoxrun:BAAALgADCgUJBQAAAA==.Greatbooty:BAABLgAECn8iAAIEAAgJKxkJRwDvAQAEAAgJKxkJRwDvAQAAAA==.Grecko:BAAALgADCgUJBQAAAA==.Gremmi:BAAALgAECgEJBwAAAA==.Greygavel:BAABLgAECn8VAAIjAAgJQCMRAwCYAgAjAAgJQCMRAwCYAgAAAA==.Grimmknight:BAAALgADCgEJAQAAAA==.Grishypally:BAAALgAECgkJAQAAAA==.Grosgland:BAAALgADCgEJAQAAAA==.Groundbeéf:BAACLgAFFH8YAAIVAAcJeSDwAAAIAgAVAAcJeSDwAAAIAgAuAAQKfykAAhUACAkJJvsAAH4DABUACAkJJvsAAH4DAAAA.Groundzero:BAAALgADCgUJBQAAAA==.Groztrazztok:BAAALgAECgYJEwAAAA==.Grungulus:BAAALgAECgcJEwAAAA==.',
Gu='Guineapig:BAEBLgAECn8UAAIIAAcJLyTdMABfAgAIAAcJLyTdMABfAgAAAA==.Gundral:BAAALgADCgIJAgAAAA==.Gunnysack:BAAALgADCggJDgAAAA==.Guzmo:BAAALgAECgEJAQABLgAECgUJBgAGAAAAAA==.',
Gy='Gyx:BAAALgAECgQJCAAAAA==.',
Ha='Haiku:BAAALgAECgEJAQAAAA==.Handanir:BAABLgAECn88AAIJAAkJmyHOBQBOAwAJAAkJmyHOBQBOAwAAAA==.Harie:BAABLgAECn8mAAIEAAgJJA7BeABsAQAEAAgJJA7BeABsAQAAAA==.Hasbula:BAAALgAECgQJBAAAAA==.Hatebound:BAAALgAECgIJAgAAAA==.Hateform:BAAALgAFFAEJAQAAAA==.',
He='Hearthcliff:BAAALgAECgQJEAAAAA==.Heihei:BAAALgADCgYJDAAAAA==.Heiny:BAACLgAFFH8MAAMjAAMJRCNSDAAOAQAbAAMJcyK3ZQATAQAjAAMJbh5SDAAOAQAuAAQKfyIABCMACQlOJnoBAPwCACMACQk7JHoBAPwCABsACAlvJr4NAO0CABwABgkEET8mAA0BAAAA.Heinyheinyho:BAACLgAFFH8GAAIHAAMJDhsjJgDbAAAHAAMJDhsjJgDbAAAuAAQKfzAABAcACAk+JLIIAOQCAAcACAk+JLIIAOQCACQABQmgIUoTAHwBAAgAAQmbIcYpAWMAAAEuAAUUAwkMACMARCMA.',
Hi='Hielle:BAAALgADCgkJCQAAAA==.Highguard:BAAALgADCgcJBwAAAA==.Himothy:BAAALgAECgEJBAAAAA==.',
Ho='Hoid:BAAALgAECgEJAgABLgAECgEJAwAGAAAAAA==.Holy:BAAALgADCgYJBgAAAA==.Holysword:BAEALgADCgYJBgABLgAECgQJBQAGAAAAAA==.Holytest:BAABLgAFFH8MAAMOAAYJTAlMFACbAQAOAAYJTAlMFACbAQAlAAUJmAFaFgDpAAAAAA==.Hoofmetoo:BAABLgAECn8yAAMjAAgJtR+BBQAzAgAjAAgJIBuBBQAzAgAbAAgJvx3IMgAfAgAAAA==.Howboudah:BAAALgADCggJCAAAAA==.',
Hu='Hulkgirl:BAAALgADCgEJAQAAAA==.Hulzar:BAABLgAECn8YAAIDAAcJlRySJgCwAQADAAcJlRySJgCwAQAAAA==.',
Hy='Hypocrisy:BAAALgAECgkJBgAAAA==.',
['Hô']='Hôlyblight:BAAALgAECgEJAQABLgAFFAUJFwAaABIZAA==.',
Ic='Iceflare:BAABLgAECn8ZAAMEAAgJihbfVAA5AgAEAAgJihbfVAA5AgAFAAQJ7gLmEwCHAAAAAA==.',
Id='Idotyouto:BAABLgAECn8yAAIEAAkJsBlQNgAnAgAEAAkJsBlQNgAnAgAAAA==.',
Ig='Igris:BAAALgAECgQJDgAAAA==.',
Ih='Ihavewater:BAAALgADCgkJDgAAAA==.',
Ik='Iktizi:BAAALgADCgEJAQAAAA==.',
Il='Ilbryen:BAAALgAECgUJBQABLgAFFAYJHgADADgeAA==.Illidori:BAABLgAECn8VAAIgAAcJ2gfglQDWAAAgAAcJ2gfglQDWAAAAAA==.Illidrag:BAABLgAECn8aAAImAAkJBxKjFQC9AQAmAAkJBxKjFQC9AQAAAA==.Ilovemoo:BAAALgAECgMJAwAAAA==.',
Im='Imblind:BAAALgADCgEJAQABLgAFFAUJEAALABQWAA==.Immortea:BAAALgAECgkJBgAAAA==.Immòrtlzed:BAACLgAFFH8WAAMdAAUJMCInBwB9AQAdAAUJMCInBwB9AQATAAEJfQcYDQBGAAAuAAQKfycAAh0ACAnvIP8GAHsCAB0ACAnvIP8GAHsCAAAA.',
In='Invective:BAAALgAECgMJAwAAAA==.',
Is='Isengard:BAAALgAECgEJAQAAAA==.Isharn:BAAALgADCgMJAwAAAA==.',
Iz='Izzyumi:BAABLgAECn8XAAIhAAcJVgxhXwBKAQAhAAcJVgxhXwBKAQAAAA==.',
Ja='Jabo:BAAALgADCgMJAwABLgAECgcJEgAGAAAAAA==.Jadelin:BAAALgAECgIJAgABLgAFFAMJBQAmADoPAA==.Jaxek:BAABLgAECn84AAIiAAkJ4CKrAQASAwAiAAkJ4CKrAQASAwAAAA==.Jaxs:BAACLgAFFH8SAAIZAAcJgBlFBgAoAgAZAAcJgBlFBgAoAgAuAAQKfyAAAhkACAlAG5kVAGgCABkACAlAG5kVAGgCAAAA.Jaylen:BAACLgAFFH8FAAIRAAMJ7hMNIQDwAAARAAMJ7hMNIQDwAAAuAAQKfxQAAhEABglqIWsaAKwBABEABglqIWsaAKwBAAAA.Jaymo:BAABLgAECn8aAAIMAAgJ1BxBCgA4AgAMAAgJ1BxBCgA4AgAAAA==.',
Je='Jebke:BAAALgAECgQJCgABLgAECgYJBwAGAAAAAA==.Jeffurry:BAAALgADCgIJAgAAAA==.Jeminia:BAAALgAECgUJCgAAAA==.Jenifur:BAABLgAECn8VAAIJAAYJrQsPbwDVAAAJAAYJrQsPbwDVAAAAAA==.Jennae:BAAALgADCgEJAQAAAA==.',
Jh='Jhope:BAABLgAFFH8IAAIQAAMJkA2ENQC8AAAQAAMJkA2ENQC8AAAAAA==.',
Ji='Jinkusu:BAAALgADCgMJAwABLgAECgkJIAAQAFkdAA==.',
Jm='Jml:BAACLgAFFH8UAAIgAAUJDyQ7CQCWAQAgAAUJDyQ7CQCWAQAuAAQKfyAAAiAACQnSIQAFAHYDACAACQnSIQAFAHYDAAAA.',
Jo='Johnny:BAAALgAECgEJAQABLgAECgkJLQAHAPwfAA==.Jopha:BAACLgAFFH8XAAMDAAcJeR41BwB5AQADAAUJfiE1BwB5AQACAAMJzhC0HQDVAAAuAAQKfy8AAwMACAlYJQAGAEcDAAMACAk2JQAGAEcDAAIABwkzIPIEAJQCAAAA.Jophr:BAAALgAECgQJAgABLgAFFAcJFwADAHkeAA==.',
Jp='Jpbruiser:BAACLgAFFH8HAAIIAAIJoB55agCwAAAIAAIJoB55agCwAAAuAAQKfz4AAggACQn2I4QIABMDAAgACQn2I4QIABMDAAAA.',
Ju='Judged:BAAALgAECgYJEQAAAA==.Juggalette:BAAALgADCgIJAgAAAA==.Jumpn:BAABLgAFFH8GAAImAAIJURXuGACXAAAmAAIJURXuGACXAAABLgAFFAYJHgAcANMaAA==.Jumpndeath:BAACLgAFFH8eAAIcAAYJ0xrvCgCNAQAcAAYJ0xrvCgCNAQAuAAQKfy0AAxwACQlNIjQHAJUCABwACAnaIjQHAJUCABsACAl9HFY9APkBAAAA.Jumpnpunch:BAABLgAECn8lAAQQAAgJaxwBGgA0AgAQAAcJQBwBGgA0AgALAAgJ7A+XKABbAQAKAAcJogwHOAALAQABLgAFFAYJHgAcANMaAA==.Junknugget:BAAALgADCgYJBgAAAA==.Justgetme:BAABLgAECn82AAMkAAkJBCaeAABeAwAkAAkJBCaeAABeAwAIAAIJAA6lGwFjAAABLgAFFAIJAgAGAAAAAA==.',
Jw='Jwad:BAABLgAECn8lAAMPAAYJBRncZQBnAQAPAAUJBRncZQBnAQAXAAIJ8QwEUwB1AAAAAA==.',
Ka='Kaan:BAAALgAECgEJBQAAAA==.Kaariel:BAAALgADCgcJCgAAAA==.Kabo:BAAALgADCgUJCQABLgAFFAYJFgAbAIMeAA==.Kaggardugar:BAAALgAECgYJBgAAAA==.Kagger:BAACLgAFFH8TAAIIAAQJPx6oIgBaAQAIAAQJPx6oIgBaAQAuAAQKf0MAAwgACQk6I+8EAH0DAAgACQk6I+8EAH0DACQAAwnNA6VEADwAAAAA.Kaiser:BAAALgADCgcJDAAAAA==.Kaitu:BAAALgAECgYJCwABLgAECgcJCQAGAAAAAA==.Kake:BAAALgAECgQJBAABLgAFFAMJAwAGAAAAAA==.Kalloh:BAABLgAECn8sAAMPAAcJMRSFbABXAQAPAAcJMRSFbABXAQAXAAIJ4RUhJAB1AAAAAA==.Kalorth:BAAALgADCgcJBwAAAA==.Karazal:BAAALgAECgYJCAAAAA==.Kardoroth:BAACLgAFFH8RAAIbAAUJwCVhIwCeAQAbAAUJwCVhIwCeAQAuAAQKfzcAAhsACQm/JvUDAFgDABsACQm/JvUDAFgDAAAA.Karibo:BAAALgADCgcJDAAAAA==.Karnaege:BAAALgADCgMJAwAAAA==.Karîba:BAACLgAFFH8ZAAQbAAYJ4xpNKgCHAQAbAAUJgBpNKgCHAQAcAAMJPxO/DgB+AAAjAAEJMguWHwBAAAAuAAQKfy0AAxsACAnTH1IfAMUCABsACAnTH1IfAMUCABwAAQkrCTVNABwAAAAA.Kassi:BAAALgADCgEJAQAAAA==.Kayfree:BAAALgAECgYJDAAAAA==.Kaõtik:BAAALgAECgkJCgAAAA==.',
Kc='Kca:BAAALgAECgUJBwAAAA==.',
Ke='Keerrilee:BAABLgAECn8XAAILAAkJ7xp2JgBqAQALAAkJ7xp2JgBqAQAAAA==.Kefka:BAAALgAECgQJBQAAAA==.Keirine:BAAALgAECgEJAwAAAA==.Kelfrost:BAAALgAECgIJAgAAAA==.Kelknight:BAABLgAECn8bAAMcAAQJ0x4gKQD0AAAbAAQJsxpVuwAMAQAcAAMJph8gKQD0AAAAAA==.Kelsaz:BAACLgAFFH8YAAMNAAYJRhoZBQCgAQANAAYJRxkZBQCgAQAhAAMJchV5CwAGAQAuAAQKfyAABCEACAkqIzISAKYCACEABwlIIzISAKYCACcABglBGPdGADgBAA0ABQlrFz8xABABAAAA.Kelsi:BAABLgAECn8VAAILAAkJLxjVIACRAQALAAkJLxjVIACRAQAAAA==.Kenný:BAAALgAECgEJAwAAAA==.Kerrìgàn:BAACLgAFFH8eAAIeAAgJABiJAAAWAgAeAAgJABiJAAAWAgAuAAQKfzAAAx4ACQlcIWkCANYCAB4ACQlcIWkCANYCACYAAQlKDZRiAC8AAAAA.Kestral:BAACLgAFFH8OAAMdAAYJPgrzGADtAAAdAAQJZQnzGADtAAASAAUJWwFNPQCxAAAuAAQKfyYAAx0ACAkMFCoUAAMCAB0ACAkMFCoUAAMCABIAAwn7CmhqAHAAAAAA.Keynis:BAAALgADCgEJAQAAAA==.',
Kh='Khalisi:BAAALgAECgYJDQAAAA==.Khejan:BAAALgADCgMJAwAAAA==.Khrask:BAAALgADCgIJAgABLgAFFAYJHgADADgeAA==.',
Ki='Kiell:BAAALgAECgYJBwAAAA==.Kinuyo:BAAALgAECgQJBAAAAA==.Kirali:BAAALgAECgYJBgAAAA==.Kiwipie:BAAALgAECgQJBAAAAA==.',
Kn='Knottyjack:BAAALgADCgMJAwAAAA==.',
Ko='Kookiie:BAACLgAFFH8YAAMmAAcJziCZAQAVAgAmAAcJziCZAQAVAgAgAAIJWQ19KwCYAAAuAAQKfyUAAyYACAkTIb4JAMYCACYABwnbJb4JAMYCACAACAkuHL0kAHYCAAAA.Kookiiez:BAAALgAECgQJBAAAAA==.Koom:BAAALgADCgYJBQAAAA==.Kosi:BAAALgAECgUJBwABLgAFFAUJDQASAIUVAA==.Kosian:BAABLgAECn8iAAIkAAgJdxNTEQCWAQAkAAgJdxNTEQCWAQAAAA==.Kosigan:BAAALgAECgIJAgABLgAFFAUJDQASAIUVAA==.',
Kp='Kpop:BAAALgADCgEJAQABLgAECgQJBAAGAAAAAA==.',
Kr='Krepuscular:BAAALgAECgMJBAAAAA==.Kroghar:BAAALgADCgYJBgAAAA==.Kromdor:BAABLgAECn8YAAIXAAgJSxoKBgBxAgAXAAgJSxoKBgBxAgAAAA==.Krosis:BAABLgAECn8bAAIbAAkJ6BzwOABTAgAbAAkJ6BzwOABTAgAAAA==.Krumee:BAAALgADCgYJBgAAAA==.',
Kt='Kthríss:BAAALgADCgMJAwAAAA==.',
Ku='Kungscott:BAAALgAECgEJAwABLgAFFAUJDAAIAIkXAA==.Kuromi:BAAALgAFFAEJAQAAAA==.',
Ky='Kynei:BAABLgAECn8WAAIgAAgJsx4OJgAgAgAgAAgJsx4OJgAgAgAAAA==.',
La='Lacasis:BAAALgADCgUJBQABLgAECgcJCQAGAAAAAA==.Larra:BAACLgAFFH8dAAQOAAYJOxTODwDbAQAOAAYJ/RPODwDbAQAlAAMJmgv8CADYAAAYAAIJ3QrQKACIAAAuAAQKfyEABCUACQnsGioPAG8CACUACAlrHSoPAG8CABgABgnvGzMtAHUBAA4ABgkRDkguAEMBAAAA.',
Le='Leman:BAAALgADCgkJFAAAAA==.Lemoncrisp:BAAALgAECgEJAQAAAA==.Leprocylarry:BAAALgADCgcJBwAAAA==.Letos:BAAALgAECgcJEgAAAA==.Levelmoo:BAAALgAECgYJCAAAAA==.Levitas:BAACLgAFFH8FAAIMAAMJ0AqXGwCfAAAMAAMJ0AqXGwCfAAAuAAQKfzEAAgwACQkrE2oQAMoBAAwACQkrE2oQAMoBAAAA.Lewieballz:BAAALgADCgMJAwABLgAECgkJIwAGAAAAAA==.',
Li='Liberater:BAAALgAECgEJAQAAAA==.Liljit:BAAALgAECgcJDgAAAA==.Lithel:BAAALgAECgcJCAAAAA==.',
Lo='Loaded:BAAALgAECgEJAQAAAA==.Lockxeno:BAABLgAECn8dAAMPAAgJOBlNOADsAQAPAAcJOBlNOADsAQAXAAEJAADhSgAAAAAAAA==.Lodidodii:BAABLgAECn8XAAIVAAgJ7AmfFABOAQAVAAgJ7AmfFABOAQAAAA==.Logics:BAACLgAFFH8IAAIYAAQJoBk1EwA0AQAYAAQJoBk1EwA0AQAuAAQKfysAAhgACQkqI9MFAN8CABgACQkqI9MFAN8CAAAA.Lon:BAABLgAECn8YAAILAAgJxxJlLAB9AQALAAgJxxJlLAB9AQAAAA==.Longsham:BAAALgADCgEJAQAAAA==.Lostea:BAAALgADCgUJBQABLgAECggJIwASAJ8XAA==.Lostmylimbs:BAACLgAFFH8LAAIcAAQJJQndCgDQAAAcAAQJJQndCgDQAAAuAAQKfysAAhwACAmbGfoRANIBABwACAmbGfoRANIBAAEuAAUUCAkeAB4AABgA.Lostmyvigor:BAABLgAFFH8HAAIdAAQJKxK7FgAJAQAdAAQJKxK7FgAJAQAAAA==.Lostvoker:BAABLgAECn8jAAMSAAgJnxe8FQAsAgASAAgJnxe8FQAsAgATAAUJehDrIgATAQAAAA==.Loueballz:BAAALgAECgkJIwAAAQ==.Lowvice:BAAALgADCgEJAQAAAA==.',
Lu='Lucarad:BAABLgAECn8yAAILAAkJXhgvEQAlAgALAAkJXhgvEQAlAgAAAA==.Lucerfer:BAAALgADCgUJBwAAAA==.Lucivia:BAABLgAECn83AAIWAAkJgRutAwBVAgAWAAkJgRutAwBVAgAAAA==.Lumafist:BAACLgAFFH8KAAILAAMJHx9SEwASAQALAAMJHx9SEwASAQAuAAQKfy8AAgsACQnQIRwIALICAAsACQnQIRwIALICAAAA.Lunirae:BAAALgADCgkJFwAAAA==.Luxarion:BAAALgAECgcJBAAAAA==.',
['Lè']='Lènneth:BAACLgAFFH8HAAIlAAMJwBYVGQDSAAAlAAMJwBYVGQDSAAAuAAQKfy0AAyUACQmCHa0KAKYCACUACQmCHa0KAKYCABgAAgnMEA9lAFsAAAAA.',
['Lí']='Líghtning:BAAALgAECggJDgAAAA==.',
['Lø']='Løstdruid:BAAALgADCgEJAQABLgAECgUJCQAGAAAAAA==.Løstpala:BAAALgAECgUJCQAAAA==.',
Ma='Magewreck:BAAALgAECgYJBgAAAA==.Mahiru:BAAALgADCgMJAwAAAA==.Majimojo:BAAALgAECgIJAwAAAA==.Makkaflocka:BAAALgAECgUJBQABLgAECggJJwAgAOMjAA==.Malleus:BAAALgADCgUJBQAAAA==.Malytheris:BAABLgAECn8iAAMkAAgJJRmqCgAEAgAkAAgJJRmqCgAEAgAIAAEJzgXjjgEnAAAAAA==.Marqis:BAAALgAECgEJAQAAAA==.Mattshanu:BAACLgAFFH8UAAIaAAYJ4BsvDQCTAQAaAAYJ4BsvDQCTAQAuAAQKfyIAAxoACQkuHrsUAHgCABoACQkuHrsUAHgCABkABAlQGnlZADIBAAAA.Mayalaran:BAAALgADCgcJDwAAAA==.Mazgruug:BAAALgAECgcJCgAAAA==.Mazkova:BAAALgAECggJEQAAAA==.Mazur:BAABLgAECn8hAAIIAAgJdSH6JABYAgAIAAgJdSH6JABYAgAAAA==.',
Mc='Mcmonkton:BAAALgAECgcJDAAAAA==.',
Me='Meirah:BAAALgADCgYJBAAAAA==.Mekkaweepz:BAAALgADCgUJBQAAAA==.Melaan:BAABLgAECn8dAAIJAAgJOByJFgCAAgAJAAgJOByJFgCAAgAAAA==.Melinadra:BAAALgAECgEJAQAAAA==.Meowmixx:BAAALgADCgYJBgAAAA==.Meowssa:BAECLgAFFH8UAAIoAAQJ3SJABACZAQAoAAQJ3SJABACZAQAuAAQKfy0AAygACQkFJR4BAEkDACgACQkFJR4BAEkDACIAAglXEcIyAGkAAAAA.Metalplipes:BAAALgADCgQJCgAAAA==.',
Mi='Midori:BAAALgAECgEJAQAAAA==.Mindleseye:BAAALgADCgQJBgAAAA==.Mindlesscon:BAABLgAECn8WAAMVAAYJ0x7YDAD1AQAVAAYJph3YDAD1AQAaAAUJXB6QPABaAQAAAA==.Minislayer:BAAALgAECgcJEQAAAA==.Minyprayers:BAACLgAFFH8bAAMYAAYJ6BV4BgBgAQAYAAUJaBp4BgBgAQAlAAEJvApyKwBOAAAuAAQKfykAAhgACQkQJScCADsDABgACQkQJScCADsDAAAA.Minywon:BAAALgADCgcJCgABLgAFFAYJGwAYAOgVAA==.Misosalty:BAACLgAFFH8KAAMLAAMJlRlmGwDcAAALAAMJUhdmGwDcAAAQAAMJcBScLgDYAAAuAAQKfzUAAwsACQnoHzAHAMUCAAsACQnoHzAHAMUCABAABgl/GdEvADIBAAAA.Misowet:BAAALgADCgYJCQABLgAFFAMJCgALAJUZAA==.',
Ml='Mlorpglorp:BAABLgAECn8hAAIEAAgJuB97PQCCAgAEAAgJuB97PQCCAgAAAA==.',
Mo='Mobaye:BAAALgAECgEJAQAAAA==.Mohjito:BAABLgAECn9CAAMLAAkJ3BzeCACjAgALAAkJ3BzeCACjAgAQAAUJHhHlSQDFAAAAAA==.Moirbius:BAAALgADCgEJAQAAAA==.Mojojojoz:BAAALgADCgUJBQAAAA==.Monkisbad:BAABLgAECn8xAAIQAAkJaSNyBADyAgAQAAkJaSNyBADyAgAAAA==.Monkma:BAAALgAECgIJAgAAAA==.Moonfire:BAAALgADCgcJDgAAAA==.Moose:BAAALgADCgYJBgAAAA==.Mooshanu:BAAALgADCgcJDAABLgAFFAYJFAAaAOAbAA==.Morguth:BAACLgAFFH8SAAMhAAUJZBerMAA0AQAhAAUJZBerMAA0AQAnAAIJUQCtIwBdAAAuAAQKfx0ABCEACQl7HSUUAJUCACEACQl7HSUUAJUCACcABAkeBLVnAKAAAA0AAgliD3pbADcAAAAA.Moriaug:BAAALgAFFAIJAgABLgAFFAUJDwAPAIwfAA==.Moriko:BAABLgAECn8VAAMOAAgJsAu0KwA9AQAOAAcJTQy0KwA9AQAYAAEJ/QSMfQAtAAAAAA==.',
Mu='Muggy:BAAALgAECgEJBAAAAA==.Murky:BAACLgAFFH8FAAIRAAIJrxOeKgCbAAARAAIJrxOeKgCbAAAuAAQKfy4AAhEACAlcH5oKAGQCABEACAlcH5oKAGQCAAAA.Musicmichael:BAAALgAECgYJCQAAAA==.',
['Mî']='Mîyagî:BAAALgAECgcJCQAAAA==.',
['Mö']='Mööbs:BAABLgAECn84AAMdAAkJKQcQFgBaAQAdAAkJKQcQFgBaAQASAAYJfQYeSwCnAAAAAA==.',
Na='Namad:BAAALgAECgYJDwAAAA==.Namphan:BAAALgADCgEJAQAAAA==.Nancybrew:BAABLgAECn8mAAMLAAkJoR+MCwB2AgALAAkJoR+MCwB2AgAKAAIJdRJ3WABtAAAAAA==.Natalie:BAAALgAECgEJAwAAAA==.Nathric:BAAALgADCgUJBQAAAA==.Navajo:BAAALgAECgcJEwAAAA==.',
Ne='Neature:BAAALgADCgMJAwAAAA==.Neoma:BAABLgAECn8fAAIPAAcJZAvVgQArAQAPAAcJZAvVgQArAQAAAA==.Nesqwik:BAAALgAECgQJCQAAAA==.Nevan:BAABLgAECn8qAAMHAAkJByTbBwD6AgAHAAkJByTbBwD6AgAIAAQJKBGmyQDdAAAAAA==.Neverender:BAAALgAECgEJAgABLgAECgYJFQAOAH0cAA==.Newlock:BAAALgAECgQJBAAAAA==.Nexi:BAAALgAECgMJAwAAAA==.',
Ni='Niang:BAAALgADCgQJBAAAAA==.Nidalee:BAAALgAECggJEQAAAA==.Nippyvixen:BAAALgAECgEJAQAAAA==.Nishu:BAAALgADCgMJAwAAAA==.',
No='Noochallange:BAABLgAECn82AAIfAAkJWCFZAQDqAgAfAAkJWCFZAQDqAgAAAA==.Norex:BAACLgAFFH8YAAQbAAYJjBQpJwCQAQAbAAUJjBQpJwCQAQAjAAEJVApaHQBIAAAcAAEJAAB+SwAAAAAuAAQKfyEAAxsACQkmE9VaAOEBABsACQmzEtVaAOEBABwABgmfCLosANkAAAAA.Norm:BAAALgAECgYJCwAAAA==.Notekk:BAAALgAECgQJBwAAAA==.Nottygerbil:BAAALgAECgMJAwAAAA==.',
Nu='Nuggie:BAABLgAECn8gAAMPAAkJ5BlhKgAjAgAPAAgJ5BlhKgAjAgAXAAEJAADGYgBJAAAAAA==.Nurf:BAAALgADCgMJAwAAAA==.Nurgal:BAAALgAECgYJCAAAAA==.Nutbind:BAAALgADCgIJAgAAAA==.Nutlips:BAAALgADCgUJCwABLgAECgMJBgAGAAAAAA==.',
Ny='Nylariaa:BAAALgAECgYJEgAAAA==.Nymia:BAABLgAECn8nAAMJAAkJMRw7HQBIAgAJAAkJMRw7HQBIAgABAAEJthjWcwBHAAAAAA==.',
['Næ']='Næon:BAABLgAECn8gAAIKAAkJcxjLFwA1AgAKAAkJcxjLFwA1AgAAAA==.',
Ob='Oblake:BAABLgAECn8YAAIRAAcJkBQmIQDwAQARAAcJkBQmIQDwAQAAAA==.',
Oc='Octosloth:BAAALgADCgEJAQAAAA==.',
Oh='Ohhashbrowns:BAAALgADCgcJBwAAAA==.',
Ok='Oku:BAAALgADCgcJBgAAAA==.',
Ol='Oldmagic:BAABLgAECn8UAAIEAAcJgglbsgACAQAEAAcJgglbsgACAQAAAA==.Olizza:BAAALgAECgIJAgABLgAECggJKQAhAKISAA==.',
Om='Omgimabeast:BAAALgAECgYJCAAAAA==.',
On='Onieva:BAAALgAECgkJDgAAAA==.',
Oo='Ooglaboogla:BAABLgAECn86AAMaAAkJWCDBBwDOAgAaAAkJWCDBBwDOAgAZAAMJQRWRggCJAAAAAA==.Oominous:BAABLgAECn8VAAIOAAYJfRzIHADGAQAOAAYJfRzIHADGAQAAAA==.',
Or='Oriah:BAAALgADCgYJBgAAAA==.Orions:BAAALgADCgQJBAAAAA==.Orygor:BAAALgADCgIJAwAAAA==.',
Os='Osserc:BAAALgAECgQJBAAAAA==.',
Ox='Oxyrotten:BAABLgAECn8hAAMbAAYJVw9vswD5AAAbAAYJJA1vswD5AAAcAAQJgA2AOwCLAAAAAA==.',
Pa='Pablo:BAABLgAECn82AAMNAAkJmSHiBgCnAgANAAkJmSHiBgCnAgAnAAEJZREShwA1AAAAAA==.Pancho:BAABLgAECn8cAAILAAkJehc+EgAbAgALAAkJehc+EgAbAgAAAA==.Pandra:BAAALgADCgEJAQAAAA==.Panttyraider:BAAALgAFFAIJAgAAAA==.Panzeria:BAABLgAECn8dAAIYAAcJPSU8CQDwAgAYAAcJPSU8CQDwAgAAAA==.Papito:BAAALgAFFAIJAgAAAA==.Parsetwo:BAAALgAECgEJAQAAAA==.Pathryis:BAAALgAECgYJBgAAAA==.Pawsome:BAAALgADCgIJAgAAAA==.',
Pl='Plank:BAAALgAECgUJBwAAAA==.Plipe:BAAALgAECgIJAQAAAA==.',
Pm='Pmon:BAAALgADCgEJAQAAAA==.',
Po='Pongo:BAAALgAECggJEQAAAA==.Ponkofox:BAACLgAFFH8MAAIVAAQJLQn1CAAKAQAVAAQJLQn1CAAKAQAuAAQKfx8AAhUACAlAFAkOANwBABUACAlAFAkOANwBAAAA.',
Pr='Prah:BAAALgAECgcJDAAAAA==.Prepared:BAAALgAECgIJAgAAAA==.Prise:BAAALgAECgMJBgAAAA==.Prisefather:BAAALgAECgYJCgAAAA==.Prisefightr:BAAALgAECgEJAQAAAA==.Prizefighter:BAAALgAECgYJDQAAAA==.Proditus:BAAALgAECgQJBwAAAA==.Proowee:BAAALgAECgkJCQAAAA==.',
Ps='Pseudoholy:BAAALgADCgEJAQAAAA==.',
Pu='Putridvigor:BAACLgAFFH8GAAIcAAMJYxuxGgDnAAAcAAMJYxuxGgDnAAAuAAQKfyAAAxwACQnbGG4LAD8CABwACQnbGG4LAD8CABsAAwmfBkcQAXIAAAAA.Puzzlewalrus:BAAALgADCgQJBAAAAA==.',
Py='Pyreiella:BAAALgADCgUJBQAAAA==.Pyroamor:BAAALgAECgEJAQAAAA==.Pyropete:BAABLgAFFH8IAAIEAAMJ8QHfggCtAAAEAAMJ8QHfggCtAAAAAA==.',
['Pä']='Pälii:BAABLgAECn8nAAMHAAkJdQcnMwByAQAHAAkJdQcnMwByAQAIAAQJhA4l4QDLAAAAAA==.',
Qc='Qcomberoo:BAAALgADCgMJAwAAAA==.',
Ra='Ragublaster:BAAALgAECgEJAQABLgAFFAYJEwASAKIZAA==.Ragz:BAAALgAECggJCwAAAA==.Ralickan:BAAALgADCgcJBQAAAA==.Ramaan:BAABLgAECn8hAAIZAAkJ+hufDgDGAgAZAAkJ+hufDgDGAgAAAA==.Ramble:BAAALgAECgcJDQAAAA==.Ravette:BAABLgAECn83AAMmAAkJvyNxAwAGAwAmAAkJvyNxAwAGAwAeAAMJnBNWHgCVAAAAAA==.Ravissante:BAABLgAECn8eAAIgAAcJ2wYIlQDYAAAgAAcJ2wYIlQDYAAAAAA==.Rawranator:BAAALgAECgYJDgAAAA==.',
Re='Reesecupthis:BAABLgAECn8fAAIkAAgJHCJeBQCiAgAkAAgJHCJeBQCiAgABLgAFFAcJFwAkABkYAA==.Remagix:BAAALgAECgEJAQAAAA==.Remix:BAAALgAECgQJBAAAAA==.Revek:BAAALgADCgEJAQAAAA==.Reveurus:BAAALgADCgcJBwABLgAECgkJKgAHAAckAA==.Rezzaleya:BAAALgADCgQJBAAAAA==.',
Rh='Rhaena:BAAALgAECgYJDQABLgAECgkJDgAGAAAAAA==.Rhonis:BAAALgAECgYJDAAAAA==.',
Ri='Riceroll:BAABLgAECn8bAAMXAAcJKiAzJAA4AQAPAAYJ6x48XQCxAQAXAAQJIB0zJAA4AQAAAA==.Rickyspanish:BAAALgAECgcJBAAAAA==.Ricochet:BAABLgAECn8wAAIHAAgJ6BWSGgAZAgAHAAgJ6BWSGgAZAgAAAA==.Rioszen:BAAALgADCgIJAgAAAA==.Riseordie:BAAALgADCgYJCAAAAA==.',
Ro='Rollmybitzup:BAABLgAFFH8FAAILAAEJdwvONwA+AAALAAEJdwvONwA+AAABLgAFFAYJEwASAKIZAA==.Ronnycoleman:BAAALgAECgMJAwAAAA==.Roofonfire:BAABLgAECn8bAAMVAAgJsgkTGQAWAQAVAAgJ7AgTGQAWAQAaAAMJvwYzdwBmAAAAAA==.Roreck:BAAALgAECgkJBAAAAA==.Rowyn:BAAALgADCgEJAQAAAA==.',
Ru='Runeka:BAACLgAFFH8GAAIOAAMJqyGiHgAjAQAOAAMJqyGiHgAjAQAuAAQKfyMAAg4ACAmZJXEHAMsCAA4ACAmZJXEHAMsCAAAA.Rusalkha:BAAALgADCgEJAQAAAA==.Ruteefear:BAABLgAECn8WAAMPAAgJnxxzKAAsAgAPAAgJnxxzKAAsAgAWAAMJUxvfEwDyAAAAAA==.',
Ry='Rybes:BAAALgAECgcJEgAAAA==.Rychesus:BAAALgADCgYJBgABLgAECgUJCQAGAAAAAA==.',
Sa='Safehaven:BAAALgAECgMJAwAAAA==.Saintcloud:BAAALgADCgkJEAAAAA==.Sairuwki:BAAALgAECgkJCQAAAA==.Samwìse:BAACLgAFFH8aAAIlAAYJFRG0BwClAQAlAAYJFRG0BwClAQAuAAQKfzYAAyUACAkzJHUOAHYCACUACAkzJHUOAHYCABgABwlKFNwnAG8BAAAA.Sandrokos:BAAALgADCgUJCgAAAA==.Sareir:BAAALgADCgMJAwAAAA==.Sarranidan:BAAALgAECgUJBQABLgAECggJIgAkAHcTAA==.Sato:BAAALgAECgEJAQAAAA==.Savagex:BAAALgADCgYJBgAAAA==.Saveena:BAAALgAECgYJEgAAAA==.',
Sc='Scarlla:BAABLgAECn8XAAIZAAkJlR66DgDGAgAZAAkJlR66DgDGAgAAAA==.Scorber:BAAALgAECgIJAgAAAA==.',
Se='Searingbear:BAAALgAECgQJBQABLgAECggJGgALAEYXAA==.Senggolbacok:BAAALgAFFAIJAgAAAA==.Senpaii:BAAALgAECgEJAwAAAA==.Senseitheta:BAAALgAECgEJAgABLgAECggJHQAPADgZAA==.Sepherios:BAAALgADCgYJBgAAAA==.Serengenuity:BAAALgAFFAIJBAAAAA==.Serenidin:BAAALgAECgEJAQAAAA==.Serenio:BAAALgAECgEJBAAAAA==.Sereniswift:BAAALgAECgQJBQAAAA==.Serephita:BAABLgAECn8uAAIEAAkJnAgcfQBjAQAEAAkJnAgcfQBjAQAAAA==.',
Sg='Sgtsnipe:BAAALgAECgQJBQAAAA==.',
Sh='Shakys:BAABLgAECn8lAAMEAAgJKRlKRgDxAQAEAAgJKRlKRgDxAQApAAEJqwgmEgApAAAAAA==.Shalaylea:BAAALgAECgYJDgAAAA==.Shamruce:BAAALgADCgYJBgAAAA==.Shamwich:BAABLgAECn8lAAMaAAgJzRP1IgC1AQAaAAgJzRP1IgC1AQAZAAQJtARIlQCAAAAAAA==.Shanondorf:BAABLgAECn8bAAMUAAgJ3xsMBQAKAgAUAAgJ5hoMBQAKAgARAAUJdxraMQD3AAAAAA==.Shark:BAABLgAECn8YAAMJAAYJ7RKwSABZAQAJAAYJ7RKwSABZAQABAAUJ/QvNRADcAAABLgAFFAYJGAAbAFEUAA==.Shaymist:BAAALgAECgMJAwAAAA==.Sheeplord:BAAALgADCgQJBgAAAA==.Sheepstealer:BAABLgAECn8+AAMSAAkJ6RZgEgA0AgASAAkJ6RZgEgA0AgATAAQJLgJJNAByAAAAAA==.Shiggyll:BAAALgAECgMJAwAAAA==.Shildo:BAABLgAECn8tAAMYAAkJhhqeEAA4AgAYAAkJhhqeEAA4AgAOAAEJQQutVAA4AAAAAA==.Shirokuma:BAAALgAECgMJAwAAAA==.Shiryunuri:BAAALgADCgUJCAAAAA==.Shizzo:BAAALgAECgYJEgAAAA==.Shockrock:BAAALgAECgQJBQAAAA==.Shybuzz:BAAALgAECggJCgAAAA==.Shøstákovich:BAAALgADCgEJAQAAAA==.',
Si='Sifen:BAABLgAFFH8MAAIIAAUJiRc7KgBCAQAIAAUJiRc7KgBCAQAAAA==.Sifting:BAAALgADCgkJCQABLgAECgkJNAASAKwhAA==.Silecra:BAAALgADCgcJBwABLgAFFAMJBgAOAKshAA==.Sinscale:BAAALgAECgQJBAABLgAFFAcJGAAIAPAdAA==.Sinswrath:BAACLgAFFH8YAAIIAAcJ8B0SCAAGAgAIAAcJ8B0SCAAGAgAuAAQKfyUAAggACAkWJIQJAEUDAAgACAkWJIQJAEUDAAAA.',
Sk='Skarre:BAACLgAFFH8DAAIgAAIJyAmZcgB8AAAgAAIJyAmZcgB8AAAuAAQKfyEAAiAABwnbHDAwADoCACAABwnbHDAwADoCAAAA.Skcusnor:BAABLgAECn8WAAIhAAkJfww2VQCLAQAhAAkJfww2VQCLAQAAAA==.Skelevyrn:BAAALgADCgEJAQAAAA==.Skimnms:BAAALgADCgUJBgAAAA==.Skrimbly:BAAALgAECgEJAQAAAA==.',
Sl='Slaye:BAAALgAECgkJEwAAAA==.',
Sm='Smiteheal:BAAALgAECgQJBAAAAA==.Smores:BAACLgAFFH8YAAIJAAYJ5R5uBwBPAgAJAAYJ5R5uBwBPAgAuAAQKfyAAAgkACQkAJaYEAEQDAAkACQkAJaYEAEQDAAEuAAUUCAkrAAkAIxwA.Smrts:BAAALgAECggJCwAAAA==.',
Sn='Snaccident:BAACLgAFFH8JAAMTAAMJdgheBwCsAAATAAMJiAJeBwCsAAASAAMJIQgBSgB4AAAuAAQKfycAAxIACQnFEQAhALgBABIACQnFEQAhALgBABMAAQnBAHJGABkAAAAA.Snaccidentsh:BAAALgADCgMJAgABLgAFFAMJCQATAHYIAA==.Snaccidentww:BAABLgAECn8UAAILAAgJEQqvMwAfAQALAAgJEQqvMwAfAQABLgAFFAMJCQATAHYIAA==.Sneakyteeth:BAABLgAECn8xAAIRAAkJ+RX/DgAjAgARAAkJ+RX/DgAjAgAAAA==.Snotzz:BAAALgAECgcJDgAAAA==.',
So='Soilworkerr:BAAALgAECgEJAQABLgAECgUJBQAGAAAAAA==.Sojukai:BAAALgAECgEJAQAAAA==.Sok:BAAALgAECgUJDgAAAA==.Solonör:BAAALgADCgcJCAAAAA==.Songi:BAABLgAECn8fAAIbAAgJFiJ4KACZAgAbAAgJFiJ4KACZAgAAAA==.Soulwhisper:BAACLgAFFH8YAAIbAAcJ1RYQGgDKAQAbAAcJ1RYQGgDKAQAuAAQKfyYAAhsACAm1JFIVAPwCABsACAm1JFIVAPwCAAAA.',
Sp='Spaghetifire:BAABLgAFFH8TAAISAAYJohk/EwCSAQASAAYJohk/EwCSAQAAAA==.Sparklybeach:BAAALgADCggJCAAAAA==.Sphyr:BAABLgAECn8jAAMIAAkJhgphkQA0AQAIAAkJKAZhkQA0AQAkAAYJvwzRIwDaAAAAAA==.Spicynoodi:BAABLgAECn8cAAMTAAgJhgfWHQA/AQATAAcJgwfWHQA/AQASAAMJ0gWQawBsAAAAAA==.Splageras:BAAALgAECgEJAQAAAA==.Spyrodruid:BAAALgAFFAEJAQABLgAFFAUJGAAcAMQeAA==.Spyromonk:BAABLgAFFH8FAAIQAAQJwBBRJAAGAQAQAAQJwBBRJAAGAQABLgAFFAUJGAAcAMQeAA==.',
Sq='Sqoots:BAABLgAECn8hAAIEAAgJDiJ4IQDtAgAEAAgJDiJ4IQDtAgAAAA==.',
St='Stankyfist:BAAALgAECgUJCAAAAA==.Starfeish:BAAALgAECgcJEAAAAA==.Stepzlol:BAAALgADCgIJAwAAAA==.Stopresistin:BAAALgAECgUJCQAAAA==.Stormsinger:BAABLgAECn8pAAMaAAkJPxcCHADoAQAaAAkJPxcCHADoAQAZAAgJDBGBTgBJAQAAAA==.Stårrßerry:BAAALgAECgIJAgAAAA==.',
Su='Succubis:BAAALgADCgIJAgAAAA==.Sugarblast:BAACLgAFFH8NAAMaAAUJIhyTCQBEAQAaAAQJIhyTCQBEAQAVAAEJAACxFgAAAAAuAAQKfyMAAhoACAn7IwwLAOcCABoACAn7IwwLAOcCAAAA.Sukker:BAAALgAECgMJBgAAAA==.Sukkler:BAAALgADCgYJCAAAAA==.Sumtingwong:BAAALgADCgYJBgAAAA==.Suou:BAACLgAFFH8eAAMDAAYJOB7MEQBaAQADAAUJyiDMEQBaAQACAAIJww7NJgCWAAAuAAQKfyUAAwMACQkMIQcfAOMBAAMABwk6IQcfAOMBAAIAAgmBIL9AAKgAAAAA.Supadoc:BAACLgAFFH8LAAIZAAMJ7x62LAAMAQAZAAMJ7x62LAAMAQAuAAQKfxcAAhkACQm9Dtc3ALUBABkACQm9Dtc3ALUBAAAA.Superchicken:BAAALgAECgIJAgAAAA==.Surfbird:BAAALgAECgYJBgAAAA==.',
Sv='Svekkê:BAAALgAECgcJBwAAAA==.',
Sw='Swagmeoutbro:BAAALgADCgIJAgAAAA==.',
Sy='Sylint:BAAALgAECgYJCQAAAA==.Sylliseas:BAAALgADCgYJBgAAAA==.Sylvara:BAAALgAECgUJBwAAAA==.Sylverhooves:BAAALgAECgYJDQAAAA==.Sylverlock:BAAALgAECgIJAgAAAA==.',
Ta='Ta:BAAALgADCgIJAgAAAA==.Tacosdk:BAAALgAECgUJCAAAAA==.Tacoss:BAAALgAECgIJAgAAAA==.Taladiira:BAAALgADCgcJAgAAAA==.Tandaley:BAAALgAECgUJBQABLgAECgkJKQAaAD8XAA==.Tandea:BAAALgAECgEJAQAAAA==.Tandragosa:BAAALgAECgMJBAABLgAECgkJKQAaAD8XAA==.Tankadiin:BAAALgAECgQJBAAAAA==.Tannica:BAAALgADCgYJBgAAAA==.Tanthyr:BAAALgAECgYJCAAAAA==.Tayswiftagos:BAAALgAECggJEgABLgAECggJGgAeAKEcAA==.',
Te='Teddy:BAAALgADCgMJAwAAAA==.Teddyy:BAAALgAECgcJBwAAAA==.Testme:BAAALgADCgYJBgAAAA==.Texazmade:BAAALgAECgUJBgAAAA==.Textacô:BAAALgAECgUJBQABLgAECgUJBgAGAAAAAA==.',
Th='Thagomizer:BAAALgADCgIJAgAAAA==.Thechadlad:BAAALgADCgYJBgAAAA==.Thedevilssin:BAACLgAFFH8FAAIoAAMJZAUNHgB9AAAoAAMJZAUNHgB9AAAuAAQKfxsAAigABwncFzMUAJMBACgABwncFzMUAJMBAAAA.Thefool:BAAALgADCgYJBgAAAA==.Theocles:BAAALgADCgYJDwAAAA==.Theodas:BAABLgAECn8VAAIbAAgJfBffRgDbAQAbAAgJfBffRgDbAQAAAA==.Therru:BAAALgADCggJGAABLgAECggJFQAOALALAA==.Thibbledorf:BAAALgAECgQJBAAAAA==.Thien:BAAALgADCgkJCQAAAA==.Thorimm:BAAALgAECgEJAQAAAA==.Throbbert:BAAALgADCgcJBwABLgAECggJGwAUAN8bAA==.Thunderhunt:BAAALgAECgQJBAABLgAECgQJCAAGAAAAAA==.Thunderwater:BAAALgAECgQJCAAAAA==.Thunis:BAABLgAFFH8FAAIgAAMJKw2fVgDJAAAgAAMJKw2fVgDJAAABLgAFFAUJDAAIAIkXAA==.',
Ti='Tigerhoods:BAAALgAECgUJCAAAAA==.Tiken:BAAALgAECgEJAwAAAA==.Tiktok:BAABLgAECn8aAAMeAAgJoRwHCQDFAQAeAAgJoRwHCQDFAQAgAAIJcQrxCAEmAAAAAA==.Tippss:BAACLgAFFH8WAAIlAAUJ0iASBgDHAQAlAAUJ0iASBgDHAQAuAAQKfzgAAyUACQnDJfgBAFQDACUACQnDJfgBAFQDAA4ACAmrFngVAA4CAAAA.Tipsygypsy:BAABLgAECn8vAAIEAAgJMwlVlQAzAQAEAAgJMwlVlQAzAQAAAA==.Tique:BAAALgAECgYJCQAAAA==.',
To='Tokenbeef:BAACLgAFFH8MAAIZAAMJxBMKPwDNAAAZAAMJxBMKPwDNAAAuAAQKfzoAAxkACQliHGkOAMkCABkACQliHGkOAMkCABoAAwlEBBJ2AGoAAAAA.Tokenshaman:BAACLgAFFH8GAAIVAAQJlwdhDADBAAAVAAQJlwdhDADBAAAuAAQKfyIAAhUABwn2ECAUAFYBABUABwn2ECAUAFYBAAAA.Torlon:BAAALgADCgEJAQAAAA==.Toxicdk:BAABLgAFFH8PAAMbAAUJPRGlVwApAQAbAAQJPRGlVwApAQAcAAIJ9QqyNgArAAAAAA==.Toxicshamy:BAACLgAFFH8GAAMVAAIJXw9TDwCPAAAVAAIJAA9TDwCPAAAaAAIJKgSbGQCIAAAuAAQKfyYABBUACQmrHK8EAI4CABUACAnXH68EAI4CABoABwnQEycpAMsBABkAAQm1GBm0AEQAAAEuAAUUBQkPABsAPREA.',
Tr='Trafficcones:BAAALgAECgMJAwAAAA==.Traugdor:BAAALgADCgkJDgAAAA==.Traylay:BAACLgAFFH8bAAIIAAYJyx/DDQC8AQAIAAYJyx/DDQC8AQAuAAQKfyEAAggACQnaJKEMACkDAAgACQnaJKEMACkDAAAA.Traylei:BAAALgADCgcJBwABLgAFFAYJGwAIAMsfAA==.Tremana:BAAALgAECgMJAwAAAA==.Trio:BAAALgADCgUJBQAAAA==.Trixaintime:BAABLgAECn8YAAIIAAcJjQlzqwArAQAIAAcJjQlzqwArAQAAAA==.',
Ts='Tsm:BAAALgADCgYJBgAAAA==.',
Tt='Ttocs:BAACLgAFFH8RAAIaAAQJTRYrHQASAQAaAAQJTRYrHQASAQAuAAQKfzIAAhoACQnJI+ACADYDABoACQnJI+ACADYDAAEuAAUUBQkMAAgAiRcA.',
Tu='Tujori:BAACLgAFFH8LAAMOAAUJiA72DgDgAAAOAAQJMBH2DgDgAAAlAAEJ6AN8LABHAAAuAAQKfx4AAyUACAmeEp0uAIkBACUACAlJC50uAIkBAA4ABwm+ErclAGcBAAAA.Turuce:BAAALgADCgYJBgAAAA==.',
Tv='Tv:BAAALgADCgcJBwABLgAECgMJAwAGAAAAAA==.',
Tw='Twherk:BAAALgAFFAEJAgABLgAFFAcJEQAOACYSAA==.Twinmoonfury:BAACLgAFFH8GAAIBAAQJFwZZJwDJAAABAAQJFwZZJwDJAAAuAAQKfzwAAwEACQn8G1oMAHwCAAEACQn8G1oMAHwCAAkABgk8E7xaAEIBAAAA.Twobit:BAAALgAECggJCQAAAA==.',
Ty='Tylann:BAAALgADCgIJAgAAAA==.Tynestra:BAABLgAECn8pAAIgAAkJrBaIKQAOAgAgAAkJrBaIKQAOAgAAAA==.',
['Tí']='Tíger:BAAALgADCgQJAwAAAA==.',
['Tü']='Tüyria:BAAALgADCgMJAwAAAA==.',
Ug='Uglydorf:BAABLgAECn8sAAIhAAkJshoMHQBiAgAhAAkJshoMHQBiAgAAAA==.',
Uh='Uhh:BAAALgAECgEJAQAAAA==.',
Ul='Ulraka:BAAALgADCgEJAQAAAA==.Ultraviolenc:BAAALgAECgEJAQAAAA==.',
Un='Unholydiver:BAAALgADCgEJAQAAAA==.',
Us='Ustoo:BAAALgAECgYJBgAAAA==.',
Va='Vaeros:BAABLgAECn8mAAISAAgJ/w9ILABvAQASAAgJ/w9ILABvAQAAAA==.Valantis:BAEALgAECgQJBQAAAA==.Valcantor:BAAALgAECgYJDAAAAA==.Vanyss:BAAALgADCgYJBgAAAA==.',
Ve='Vekz:BAABLgAECn8tAAIHAAkJ/B9/EQB0AgAHAAkJ/B9/EQB0AgAAAA==.Velazq:BAAALgADCgEJAgAAAA==.Velicia:BAABLgAECn8jAAICAAgJnxqODgDrAQACAAgJnxqODgDrAQAAAA==.Velithice:BAAALgAECgYJBwAAAA==.Venture:BAAALgAECgQJBAAAAA==.',
Vo='Voidnjoyr:BAAALgAECgEJAQAAAA==.Volcanicbird:BAAALgAFFAEJAQAAAA==.',
Wa='Walsun:BAAALgADCgcJDQABLgAECgkJKQAaAD8XAA==.Warheadx:BAAALgAECgQJBAAAAA==.Warhéad:BAAALgAECgUJDwAAAA==.Wartonxp:BAABLgAECn8sAAIYAAgJfx5ADgCfAgAYAAgJfx5ADgCfAgAAAA==.Waterbôy:BAACLgAFFH8XAAMaAAUJEhl4GAAtAQAaAAQJEhl4GAAtAQAZAAMJfQs7SQCtAAAuAAQKfzgABBoACQnoISgKAKgCABoACQnoISgKAKgCABkABQliCZdnAPAAABUAAgktBQgoAFwAAAAA.Waynee:BAAALgAECgcJDAAAAA==.',
We='Weepylight:BAAALgAECgMJAwAAAA==.Weissbrew:BAAALgADCgUJBQAAAA==.',
Wh='Wheezy:BAAALgAFFAIJAgAAAA==.Whoasked:BAACLgAFFH8NAAISAAUJhRX9IwAWAQASAAUJhRX9IwAWAQAuAAQKfzkAAxIACQmuJWACAEUDABIACQmuJWACAEUDABMABglJFyscAE8BAAAA.',
Wi='Wiggle:BAABLgAECn88AAIFAAkJQyJqAAAUAwAFAAkJQyJqAAAUAwAAAA==.Wildslayer:BAAALgADCgUJBQAAAA==.',
Wo='Wolf:BAAALgAECgEJAQAAAA==.',
Wt='Wtfheal:BAACLgAFFH8RAAIOAAcJJhIcEQDIAQAOAAcJJhIcEQDIAQAuAAQKfyUAAg4ACAkaI7QFAPMCAA4ACAkaI7QFAPMCAAAA.',
Wz='Wza:BAAALgADCgEJAQAAAA==.',
Xa='Xalash:BAAALgADCgEJAQAAAA==.Xanistra:BAACLgAFFH8cAAIPAAYJ8BhXIQCPAQAPAAYJ8BhXIQCPAQAuAAQKfyUAAw8ACQkqH0oNABADAA8ACQkqH0oNABADABcABAm/HFUtAAgBAAAA.Xaylor:BAAALgADCgcJCgAAAA==.',
Xg='Xgamesmode:BAAALgADCgUJBgABLgAFFAMJCgALAB8fAA==.',
Xz='Xzlemina:BAAALgAECgcJCQAAAA==.',
Ya='Yalaforth:BAABLgAECn8mAAIIAAkJIBPFSwDLAQAIAAkJIBPFSwDLAQAAAA==.Yamashaman:BAACLgAFFH8FAAIZAAMJmhrhMwDyAAAZAAMJmhrhMwDyAAAuAAQKfz0AAxkACQlwIPoFAD4DABkACQlwIPoFAD4DABoAAgnGB2WkACMAAAEuAAUUBQkLABsAtQwA.Yardgnome:BAACLgAFFH8HAAIJAAMJxhFBNwDAAAAJAAMJxhFBNwDAAAAuAAQKfxoAAgkACAkfEskyAMABAAkACAkfEskyAMABAAAA.',
Ye='Yebefd:BAAALgADCgcJBwAAAA==.',
Yu='Yungbluudd:BAABLgAFFH8IAAIRAAMJhB/hGwAcAQARAAMJhB/hGwAcAQAAAA==.',
Za='Zaleth:BAAALgAECgQJBQAAAA==.Zaliel:BAAALgAECgEJAgAAAA==.Zamasu:BAABLgAECn8nAAIgAAgJ4yNQDwC2AgAgAAgJ4yNQDwC2AgAAAA==.Zapmybitzup:BAACLgAFFH8HAAIVAAMJbw5HCwDaAAAVAAMJbw5HCwDaAAAuAAQKfxUAAhUABgnRFvkWADEBABUABgnRFvkWADEBAAEuAAUUBgkTABIAohkA.Zaroneus:BAAALgADCgUJBQAAAA==.Zaszadin:BAECLgAFFH8aAAIIAAYJRCINCAAGAgAIAAYJRCINCAAGAgAuAAQKfycAAggACQlfI+sZAM0CAAgACQlfI+sZAM0CAAAA.Zaszhadoom:BAEALgAECgcJCQABLgAFFAYJGgAIAEQiAA==.Zaxxon:BAABLgAECn80AAMSAAkJrCF2BAAKAwASAAkJrCF2BAAKAwATAAEJDQ3LPgA0AAAAAA==.',
Ze='Zekt:BAAALgADCgQJBAAAAA==.Zelo:BAAALgAECgYJCwAAAA==.Zensi:BAAALgAECgEJAQAAAA==.Zerax:BAABLgAECn8yAAIdAAkJcRp6CABWAgAdAAkJcRp6CABWAgAAAA==.',
Zi='Zigfury:BAAALgAECgYJDwAAAA==.Zillagoth:BAAALgAECgUJBgAAAA==.Zira:BAABLgAECn80AAIKAAkJEROyIQDmAQAKAAkJEROyIQDmAQAAAA==.',
Zo='Zombiebrainz:BAAALgAECgUJCQAAAA==.Zombiebubble:BAAALgAECgkJEQAAAA==.Zoìdberg:BAACLgAFFH8VAAIZAAMJyiG9JwAiAQAZAAMJyiG9JwAiAQAuAAQKfz0AAhkACQmDIbMHAPoCABkACQmDIbMHAPoCAAAA.',
Zs='Zselk:BAAALgADCgYJCAAAAA==.',
Zu='Zubzer:BAABLgAECn8dAAIbAAkJsBm4LgAwAgAbAAkJsBm4LgAwAgAAAA==.',
Zz='Zzor:BAACLgAFFH8hAAIEAAYJDB3vIgCwAQAEAAYJDB3vIgCwAQAuAAQKfyUAAgQACQkrJREPAE8DAAQACQkrJREPAE8DAAAA.Zzorfel:BAAALgAECgcJCAABLgAFFAYJIQAEAAwdAA==.Zzorshock:BAAALgAECgYJDAABLgAFFAYJIQAEAAwdAA==.',
['Ði']='Ðii:BAAALgAECgMJAwAAAA==.',
['ßl']='ßlue:BAACLgAFFH8HAAIEAAMJDQUnfQDEAAAEAAMJDQUnfQDEAAAuAAQKfywAAgQACQmWFaY4AB8CAAQACQmWFaY4AB8CAAEuAAUUBAkFABAAHxAA.',
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
