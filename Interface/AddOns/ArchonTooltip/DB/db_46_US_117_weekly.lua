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

local lookup = {'Warrior-Fury','Warrior-Arms','Paladin-Retribution','Druid-Restoration','Warlock-Demonology','Unknown-Unknown','Paladin-Protection','Hunter-BeastMastery','Monk-Brewmaster','Paladin-Holy','Mage-Frost','Warlock-Affliction','Warlock-Destruction','Monk-Mistweaver','DemonHunter-Devourer','Druid-Guardian','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Elemental','DeathKnight-Unholy','Rogue-Subtlety','Monk-Windwalker','Hunter-Survival','Hunter-Marksmanship','Warrior-Protection','Evoker-Augmentation','Mage-Arcane','Priest-Discipline','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Druid-Balance','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Frost','Priest-Holy','Mage-Fire','Druid-Feral','Rogue-Assassination','Rogue-Outlaw',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Acheros:BAAALgADCgEJAQAAAA==.Actionfigure:BAABLgAECn8nAAMBAAkJFSKaDACaAgABAAkJFSKaDACaAgACAAEJ7AY0RwAoAAAAAA==.',
Ad='Adessa:BAAALgAECgQJBgAAAA==.Adgavery:BAABLgAECn8bAAIDAAgJGg/jgwBcAQADAAgJGg/jgwBcAQAAAA==.Adielia:BAABLgAECn8hAAIEAAgJUx1cGQByAgAEAAgJUx1cGQByAgAAAA==.',
Ae='Aeleara:BAAALgAECgUJBQABLgAECgkJMAAFAGcaAA==.Aellip:BAAALgADCgEJAQAAAA==.Aeskir:BAAALgAECgcJAQAAAA==.Aevalaana:BAAALgAECgYJBgAAAA==.',
Af='Afton:BAAALgADCgMJAwAAAA==.',
Ah='Ahnho:BAAALgADCgQJBAAAAA==.',
Ak='Akaim:BAAALgADCgIJAwAAAA==.Aksa:BAAALgAFFAMJAwAAAA==.',
Al='Alantharia:BAAALgADCgMJAwABLgAECgUJCQAGAAAAAA==.Alexious:BAACLgAFFH8XAAIHAAUJPyEyAwBpAQAHAAUJPyEyAwBpAQAuAAQKfyQAAgcACAlWIkIDAOwCAAcACAlWIkIDAOwCAAAA.Alkapwnn:BAAALgAECgUJDAAAAA==.Almønd:BAAALgAECgEJAQAAAA==.Aloefox:BAAALgADCgkJKQAAAA==.Alofyxe:BAABLgAECn8oAAIIAAkJMCA4DQDeAgAIAAkJMCA4DQDeAgAAAA==.Alopix:BAAALgAECgIJAgAAAA==.Altagravee:BAAALgADCgQJBAAAAA==.Altdiezzel:BAAALgAECgkJCQAAAA==.Altffour:BAABLgAFFH8NAAIJAAMJvQO2GACnAAAJAAMJvQO2GACnAAAAAA==.Alulla:BAACLgAFFH8YAAIBAAYJExg2DgCBAQABAAYJExg2DgCBAQAuAAQKfyIAAgEACAndItATAEwCAAEACAndItATAEwCAAAA.Alunira:BAABLgAECn85AAMKAAkJmRxpEwB3AgAKAAkJmRxpEwB3AgADAAkJ5RLwTADWAQAAAA==.Alïwen:BAAALgAECgEJAQAAAA==.',
Am='Amberrfrost:BAABLgAECn8gAAILAAgJwgWfrgAfAQALAAgJwgWfrgAfAQAAAA==.Amberveil:BAAALgADCgYJBgAAAA==.Amex:BAAALgAECgEJAQAAAA==.',
An='Andark:BAAALgAECgMJAwAAAA==.Angryhtr:BAAALgAECgYJCQAAAA==.Angrylina:BAAALgAECgEJAQAAAA==.Anumo:BAAALgAECgEJAQAAAA==.',
Ap='Aphox:BAABLgAECn8wAAQFAAkJZxpULgAZAgAFAAkJIRZULgAZAgAMAAcJ1xerDAB/AQANAAMJLBMULABgAAAAAA==.Apokalypto:BAAALgAECgYJCQAAAA==.',
Ar='Arachnida:BAAALgADCgcJDAAAAA==.Arairi:BAAALgAECgQJBAABLgAECgYJEQAGAAAAAA==.Aravera:BAAALgAECgMJAwAAAA==.Araxes:BAAALgAECgMJBwAAAA==.Arcanefox:BAABLgAECn8YAAILAAcJmwtApwAqAQALAAcJmwtApwAqAQAAAA==.Arcenius:BAAALgAECgUJBgAAAA==.Arcåedeå:BAAALgAECgEJAQAAAA==.Ardelan:BAAALgADCggJCgAAAA==.Argangus:BAAALgADCgUJBQAAAA==.Arîse:BAAALgADCgUJCAAAAA==.',
As='Ashgold:BAAALgAECgEJAQAAAA==.Ashoggal:BAAALgADCgQJBgAAAA==.Ashyl:BAAALgAECgEJAQAAAA==.Aslunay:BAABLgAECn8jAAIDAAYJRwxwyADwAAADAAYJRwxwyADwAAAAAA==.Assine:BAAALgADCgIJAgABLgAECgcJBwAGAAAAAA==.Astanis:BAABLgAECn8WAAIOAAgJyAe5UwAEAQAOAAgJyAe5UwAEAQAAAA==.Asteriia:BAABLgAECn8vAAIPAAgJZQ97YgBXAQAPAAgJZQ97YgBXAQAAAA==.',
At='Athhena:BAAALgADCgQJBgAAAA==.Atomskdmn:BAAALgADCgEJAQAAAA==.',
Au='Augustino:BAAALgAECgIJAgAAAA==.',
Av='Avraelia:BAAALgAECgYJCwAAAA==.',
Aw='Awakemoon:BAABLgAECn8aAAIQAAgJnyTeAwDWAgAQAAgJnyTeAwDWAgAAAA==.',
Az='Azarazan:BAAALgADCgYJCAAAAA==.Azaria:BAAALgADCgkJDQABLgAECgEJAQAGAAAAAA==.Azenderv:BAABLgAECn8hAAILAAgJJwXWrAAiAQALAAgJJwXWrAAiAQAAAA==.Azka:BAABLgAECn8rAAIDAAgJWyOpGgCaAgADAAgJWyOpGgCaAgAAAA==.Azkadk:BAAALgAECggJEwAAAA==.Azkamage:BAAALgAECgYJCQAAAA==.Azshaloria:BAAALgAECgYJDgAAAA==.Azter:BAAALgADCgMJAwAAAA==.Azzline:BAAALgADCgcJBwAAAA==.',
Ba='Babybilly:BAABLgAECn8VAAIDAAgJ/gwCjgBKAQADAAgJ/gwCjgBKAQAAAA==.Baddieelf:BAAALgAECgYJEAAAAA==.Bakkasura:BAAALgAFFAEJAQABLgAFFAIJAgAGAAAAAA==.Balduran:BAAALgADCgMJAwAAAA==.Baludis:BAAALgAECgYJCgAAAA==.Bamff:BAABLgAECn8ZAAILAAgJSBn8XwC6AQALAAgJSBn8XwC6AQAAAA==.Bananadragon:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Bast:BAACLgAFFH8HAAIRAAMJNBQKCADAAAARAAMJNBQKCADAAAAuAAQKfyUAAxEACAlqIYoCAMwCABEACAlqIYoCAMwCABIAAgk7CWxrACsAAAEuAAUUBQkLAAkAowkA.Bastbrew:BAABLgAFFH8LAAIJAAUJown0LADqAAAJAAUJown0LADqAAAAAA==.Basthara:BAABLgAFFH8FAAIQAAQJLgg7GQCsAAAQAAQJLgg7GQCsAAABLgAFFAUJCwAJAKMJAA==.Batracio:BAABLgAECn8uAAMPAAkJshWqMwDsAQAPAAkJohSqMwDsAQASAAYJsRV9KAAlAQAAAA==.Batrancho:BAAALgADCgQJBAAAAA==.Batshiz:BAAALgADCgUJBQAAAA==.',
Be='Bearlylivin:BAAALgAECgEJAgABLgAECgcJCwAGAAAAAA==.Beerox:BAAALgADCgYJBgAAAA==.Belindah:BAAALgADCgcJDAABLgAECggJHgAEAFITAA==.Bellemore:BAAALgAECggJEgAAAA==.Benif:BAACLgAFFH8VAAMBAAYJCR/yEQBlAQABAAUJ9SLyEQBlAQACAAEJWA9MNwBPAAAuAAQKf0EAAwEACQk7JQoEAB8DAAEACQk7JQoEAB8DAAIABQlmJOkUAKwBAAAA.Bera:BAAALgAECgEJAQAAAA==.Bertodruid:BAAALgADCgYJBgAAAA==.Bertorod:BAABLgAECn8iAAITAAkJkx9DCwCiAgATAAkJkx9DCwCiAgAAAA==.',
Bh='Bhaall:BAABLgAECn8WAAIUAAYJ4AeA8wCuAAAUAAYJ4AeA8wCuAAAAAA==.',
Bi='Bigbitehotdo:BAABLgAFFH8KAAIOAAMJUBMUNAC4AAAOAAMJUBMUNAC4AAABLgAFFAQJFwAUANUlAA==.Bigboppa:BAAALgADCgEJAQAAAA==.Bigknife:BAABLgAECn8bAAIVAAYJCBcaJQBdAQAVAAYJCBcaJQBdAQAAAA==.Bigstunna:BAAALgADCgMJBAAAAA==.Bigtommybuns:BAAALgAECgMJBAAAAA==.Binkyfiasco:BAABLgAECn82AAMJAAkJqySJAQBRAwAJAAkJqySJAQBRAwAWAAEJphiPeQA3AAAAAA==.',
Bl='Blaqlight:BAAALgADCgEJAQAAAA==.Blockybird:BAAALgAECgIJAgAAAA==.Bloodstoned:BAAALgAECgEJAQAAAA==.Bloodtank:BAAALgAECgYJEgAAAA==.',
Bm='Bmanblastmas:BAAALgAECgEJAQAAAA==.',
Bo='Bobquat:BAAALgADCgIJAwAAAA==.Bolcy:BAACLgAFFH8OAAQXAAQJTxJIEwAlAQAXAAQJahFIEwAlAQAIAAQJ0Ay6RwALAQAYAAEJyAFeLQA9AAAuAAQKfxkABAgACAnSGxRMALEBAAgABwmWHxRMALEBABgABAm1Eg9RAAkBABcAAQkrEKBXAEMAAAAA.Bonaparte:BAAALgADCgYJBgAAAA==.Bonerott:BAAALgAECgcJCAAAAA==.Boogat:BAABLgAECn8gAAIZAAcJaAU2LgC9AAAZAAcJaAU2LgC9AAAAAA==.Boonkgang:BAAALgADCgEJAQAAAA==.Bowjangles:BAAALgADCgUJBQAAAA==.',
Br='Brahd:BAAALgAECggJCAAAAA==.Brauck:BAACLgAFFH8WAAIFAAUJ8SJgJQCSAQAFAAUJ8SJgJQCSAQAuAAQKfyUAAw0ACAmvIEUYAIgBAAUABQnSIdFSAM8BAA0ABQk3H0UYAIgBAAEuAAUUBwkWABoAaRkA.Brewbrewbrew:BAAALgAECgMJAwAAAA==.Brittarcher:BAAALgAECgcJDAAAAA==.Brixlo:BAAALgAFFAEJAQAAAA==.',
Bu='Bubblegum:BAAALgADCgMJAQAAAA==.Buffmuffin:BAAALgAECgEJAgAAAA==.Bugslyfe:BAAALgADCggJCAAAAA==.Bullcat:BAAALgADCgEJAQAAAA==.Bunbohue:BAABLgAECn8XAAIPAAcJtROSWQCVAQAPAAcJtROSWQCVAQAAAA==.Burblbiblr:BAAALgAECgMJAwAAAA==.Burni:BAAALgAECgQJBAAAAA==.Burningbubba:BAAALgAECgcJBgAAAA==.Burp:BAACLgAFFH8cAAQFAAgJ+BjVJACUAQAFAAYJwxfVJACUAQANAAMJqRYXEACoAAAMAAIJUySIFQBdAAAuAAQKfysABA0ACAl6JeQUAKMBAAUABgm2JZ80ADkCAA0ABAmCJOQUAKMBAAwAAwnqJI4OAEgBAAAA.Burped:BAAALgAECgQJCAAAAA==.',
['Bü']='Büllseye:BAAALgAECgEJAQAAAA==.',
Ca='Caadonnu:BAAALgAECgYJCAAAAA==.Cambrier:BAACLgAFFH8OAAIBAAMJjh5oKAAAAQABAAMJjh5oKAAAAQAuAAQKf0YAAgEACQlgJKIDACkDAAEACQlgJKIDACkDAAAA.Canol:BAAALgADCgEJAQAAAA==.Cardinal:BAAALgAECgcJEAAAAA==.Carynden:BAAALgAECgYJBgAAAA==.Castbo:BAABLgAFFH8IAAILAAMJRiD2ZQASAQALAAMJRiD2ZQASAQAAAA==.Caylie:BAAALgADCgQJBgAAAA==.Cazbirkzul:BAAALgADCgEJAQAAAA==.',
Ce='Celeniel:BAABLgAFFH8IAAMbAAQJbgZPAgDCAAAbAAQJ6wJPAgDCAAALAAIJoQgnngCJAAAAAA==.Celorne:BAAALgADCgEJAQAAAA==.Cerestra:BAAALgADCgEJAQAAAA==.Cerostus:BAAALgAECgUJBQAAAA==.',
Ch='Chaladaug:BAAALgAECgIJAQAAAA==.Chaladk:BAAALgAECgcJBwAAAA==.Charcharwar:BAABLgAECn9CAAICAAcJ2BgEGACQAQACAAcJ2BgEGACQAQAAAA==.Charknight:BAAALgAECgQJDgAAAA==.Charmaldin:BAAALgADCgMJAwAAAA==.Chatdodu:BAAALgAECgYJEQAAAA==.Chatnoir:BAABLgAECn8VAAIIAAgJwAUzfAA5AQAIAAgJwAUzfAA5AQAAAA==.Chulu:BAAALgADCgcJCwAAAA==.Chunklleria:BAAALgAECgMJBAABLgAECgkJNAABANUiAA==.Chunks:BAABLgAECn80AAQBAAkJ1SL6BwDZAgABAAkJ1SL6BwDZAgAZAAcJ3RiiEQDtAQACAAcJyBE8HwBZAQAAAA==.Chunkvourer:BAAALgADCgUJAwABLgAECgkJNAABANUiAA==.',
Ci='Cinci:BAAALgADCgkJCgAAAA==.Cinderazer:BAAALgAECgMJAQAAAA==.Cipherdam:BAAALgAECgMJAwAAAA==.',
Co='Colesiaw:BAAALgAECgEJAQAAAA==.Colress:BAAALgAFFAEJAQAAAA==.Conduit:BAAALgAECgYJDAAAAA==.Cormier:BAAALgAECgQJCgABLgAECgcJDwAGAAAAAA==.Covidvax:BAAALgADCgEJAQAAAA==.',
Cp='Cptbreezy:BAAALgADCgQJBAAAAA==.',
Cr='Cronnie:BAAALgAECgMJCAAAAA==.Cryodormu:BAAALgAECgYJCgAAAA==.',
Ct='Ctrlaltd:BAAALgAECgEJAQAAAA==.',
Cu='Cubo:BAAALgADCgEJAQAAAA==.',
Cw='Cwarr:BAACLgAFFH8MAAMDAAMJkRedYgDWAAADAAMJhBGdYgDWAAAHAAIJVhXHDwB1AAAuAAQKfyUAAwcABwltIwwHAGMCAAcABwltIwwHAGMCAAMABwmoDhufAC0BAAEuAAUUBgkWABkAnhsA.',
Cy='Cyrcee:BAAALgADCggJCAABLgAECggJHgAEAFITAA==.',
Da='Dabast:BAAALgAECgMJBAABLgAFFAUJCwAJAKMJAA==.Daddyluis:BAAALgAECgQJBwAAAA==.Daddywarbuck:BAAALgAECgEJAQAAAA==.Danat:BAAALgAECgEJAQAAAA==.Dandanh:BAAALgADCggJDgAAAA==.Dandathun:BAAALgAECgMJAwAAAA==.Dankbo:BAACLgAFFH8IAAIcAAIJLiVmKwDSAAAcAAIJLiVmKwDSAAAuAAQKf0MAAhwACQmAJlYAAPYDABwACQmAJlYAAPYDAAAA.Dankbro:BAAALgADCgUJBQAAAA==.Darkcoffee:BAABLgAFFH8IAAMHAAMJTxlXDACkAAAHAAIJdRxXDACkAAADAAEJAxMuogBLAAAAAA==.Darkivie:BAABLgAECn8VAAIIAAgJlQJmrgDWAAAIAAgJlQJmrgDWAAABLgAFFAMJDgAaAPkAAA==.Darkjoker:BAAALgAECgMJAwAAAA==.Darthmama:BAAALgADCgIJAgAAAA==.',
Dc='Dcbuster:BAABLgAECn8nAAIBAAgJbRdDMQDoAQABAAgJbRdDMQDoAQAAAA==.',
De='Deathshrimp:BAAALgADCgcJCwAAAA==.Delaylea:BAAALgAECgUJBgAAAA==.Demonhusk:BAAALgAECgYJDAAAAA==.Demoni:BAAALgADCgcJBwAAAA==.Demonicsword:BAAALgAECgYJCwAAAA==.Demonz:BAAALgADCgcJCgAAAA==.Denaheal:BAAALgADCgkJDgABLgAECggJGQAIAAUTAA==.Denissa:BAAALgAECgQJBAAAAA==.Devildj:BAAALgAECgcJDAAAAA==.',
Dh='Dhampyra:BAABLgAECn8gAAIdAAkJkB68DQBzAgAdAAkJkB68DQBzAgAAAA==.',
Di='Dianasia:BAAALgAECgQJBAAAAA==.Dietdrkelps:BAAALgAECgQJBAABLgAECgcJGwABAA8bAA==.Dietmountdew:BAAALgAECgUJCQAAAA==.Dimitrios:BAAALgAECgQJBwAAAA==.Dingadinga:BAAALgAECgYJEQAAAA==.Dirtlicker:BAAALgADCgIJAgAAAA==.Disconnect:BAAALgAECgYJEwAAAA==.Divindragosa:BAAALgAECgUJBQAAAA==.Dixxonciderr:BAACLgAFFH8XAAIeAAUJRRlDDwCMAQAeAAUJRRlDDwCMAQAuAAQKf0kABB4ACQkgIO8BAGEDAB4ACQkgIO8BAGEDAB8ABgnhFUMMAEEBABoABQmaBXBxAHYAAAAA.',
Dk='Dkjaypim:BAAALgAECgIJAgAAAA==.Dkjes:BAAALgADCgEJAQAAAA==.',
Dm='Dmoe:BAABLgAECn8aAAILAAYJQBZBhgBkAQALAAYJQBZBhgBkAQAAAA==.',
Do='Dorkdark:BAAALgAECgMJAwAAAA==.',
Dr='Dragonflyer:BAAALgAFFAEJAQABLgAFFAEJAQAGAAAAAA==.Drioksis:BAABLgAECn8XAAITAAYJjg6XUQDhAAATAAYJjg6XUQDhAAAAAA==.Drshaboinkyy:BAACLgAFFH8LAAIPAAUJzxJmCQCUAQAPAAUJzxJmCQCUAQAuAAQKfxQAAw8ACAmYIgIuAEUCAA8ACAmYIgIuAEUCABEABwlEA8UqADYAAAAA.Drshbuinky:BAAALgAECgYJBwAAAA==.Druyalulz:BAAALgAECgcJDwAAAA==.',
Du='Duckboy:BAAALgADCgUJBwAAAA==.Duluekin:BAAALgAECgMJBQAAAA==.Dumag:BAABLgAECn8lAAIJAAgJOyK3CgCAAgAJAAgJOyK3CgCAAgAAAA==.Duplicate:BAACLgAFFH8fAAILAAQJ0RH+VAAzAQALAAQJ0RH+VAAzAQAuAAQKf0oAAgsACQlUISQQAPUCAAsACQlUISQQAPUCAAAA.Durto:BAAALgAECgIJAgABLgAECgQJCAAGAAAAAA==.Dustdruid:BAABLgAFFH8VAAIgAAUJzhYCGwAqAQAgAAUJzhYCGwAqAQAAAA==.Dustlock:BAAALgAECgQJBAAAAA==.',
Dw='Dwighthowelf:BAAALgAECgEJAgAAAA==.',
Dy='Dyorah:BAAALgADCgYJBgAAAA==.',
Eb='Ebonsnoot:BAAALgADCgEJAQAAAA==.',
Ee='Eender:BAAALgADCgcJDgAAAA==.',
Eg='Eggrolls:BAAALgAECgQJEAAAAA==.',
El='Elfrafa:BAAALgAECgEJAQAAAA==.Elif:BAAALgADCgEJAQAAAA==.Eliotyy:BAAALgADCgYJCgAAAA==.Ellcrys:BAABLgAECn8wAAIEAAkJ+RLSLgDgAQAEAAkJ+RLSLgDgAQAAAA==.Elletta:BAAALgAECgIJCQAAAA==.Ellssa:BAABLgAECn8eAAILAAcJlwRV1gDjAAALAAcJlwRV1gDjAAAAAA==.Elmamonster:BAAALgAECgQJBwAAAA==.',
Em='Emerick:BAAALgADCgYJBQAAAA==.Emillie:BAAALgAECgYJEQAAAA==.',
Eo='Eobeob:BAAALgAECggJDwAAAA==.',
Ep='Epora:BAAALgADCgEJAQABLgAECgEJAQAGAAAAAA==.',
Er='Ersande:BAAALgADCggJCwAAAA==.',
Es='Estellia:BAAALgADCgUJBQAAAA==.Estheban:BAABLgAECn9AAAQeAAkJ8SMSAQCcAwAeAAkJ8SMSAQCcAwAfAAUJwheqCgBkAQAaAAMJ4QhGjQAwAAAAAA==.',
Ex='Exodia:BAAALgAECgYJCQAAAA==.',
Fa='Face:BAABLgAECn8qAAIPAAgJ3xbjNwDbAQAPAAgJ3xbjNwDbAQAAAA==.Faelila:BAAALgADCgYJBgAAAA==.Fairgrim:BAAALgAECgYJDgAAAA==.Falin:BAACLgAFFH8HAAIDAAMJBQRofACdAAADAAMJBQRofACdAAAuAAQKf3EAAgMACQmvHt4aAJkCAAMACQmvHt4aAJkCAAAA.Falthras:BAAALgAECgYJDAAAAA==.Fanethben:BAAALgAECgYJCwAAAA==.Faqueuedark:BAACLgAFFH8IAAMFAAMJUA+wegC/AAAFAAMJUA+wegC/AAAMAAEJVBdmIQBMAAAuAAQKfx8ABAUACAmPIFcrAGICAAUACAkDIFcrAGICAAwAAgkXIQMYALsAAA0AAQkAAEZuADkAAAAA.Faqueueeight:BAAALgAFFAEJAQABLgAFFAMJCAAFAFAPAA==.Faqueuetoo:BAAALgAECgUJBAABLgAFFAMJCAAFAFAPAA==.Fara:BAAALgAECgIJAgAAAA==.Fatsloth:BAAALgAECgIJBQAAAA==.Fatébringer:BAAALgAECgMJAwABLgAECgcJDgAGAAAAAA==.Fazt:BAAALgADCgUJDQAAAA==.',
Fe='Feironos:BAABLgAECn8UAAIfAAMJygRCHABiAAAfAAMJygRCHABiAAAAAA==.Felray:BAAALgADCgUJCAAAAA==.Ferairi:BAAALgAECgQJCgABLgAECgYJEQAGAAAAAA==.Fereir:BAAALgADCgQJBAAAAA==.Ferndavia:BAABLgAECn8ZAAIIAAgJBRM+YgB0AQAIAAgJBRM+YgB0AQAAAA==.',
Fi='Fiist:BAAALgADCgYJDgAAAA==.Filigree:BAAALgADCgYJBgAAAA==.Fimtastic:BAABLgAECn8lAAMhAAkJlg3yRACMAQAhAAkJlg3yRACMAQATAAYJ2wMRawCWAAAAAA==.Finasy:BAABLgAECn9EAAQiAAkJ+yOIAgAgAwAiAAkJ+yOIAgAgAwAUAAQJxhJj1gDWAAAjAAEJ4g9IFwAzAAAAAA==.Finnicka:BAAALgAECgYJBwAAAA==.Firefaux:BAAALgAECgEJAQAAAA==.Fireouch:BAAALgAECgEJAQAAAA==.Firevag:BAAALgAECgMJAwAAAA==.Fistymisty:BAAALgAECggJDAAAAA==.',
Fl='Flaynpray:BAAALgAECgcJAgAAAA==.Flopsie:BAAALgAECgkJDwAAAA==.',
Fo='Fonzsupreme:BAABLgAECn8YAAILAAYJniKkVwAyAgALAAYJniKkVwAyAgABLgAFFAUJFQAZAK0hAA==.Foxkit:BAAALgAECgEJAgAAAA==.Foxrawruwu:BAAALgAFFAEJAQAAAA==.',
Fr='Fredox:BAAALgADCgcJBwAAAA==.Freemilk:BAAALgAECgIJAwAAAA==.Frostbight:BAAALgADCgUJCwAAAA==.Frostyflake:BAAALgADCgUJBQAAAA==.',
Fu='Furearia:BAAALgAECgMJAwAAAA==.Furrybowner:BAABLgAECn8YAAIIAAYJnRWqewA6AQAIAAYJnRWqewA6AQAAAA==.',
['Fó']='Fóx:BAAALgAFFAEJAQAAAA==.',
Ga='Gabrielfury:BAAALgAECgkJCQAAAA==.Gaelai:BAAALgAECgUJDAAAAA==.Galeriel:BAACLgAFFH8aAAIkAAUJliHrBQDhAQAkAAUJliHrBQDhAQAuAAQKf0cAAiQACQkfHyYGAAkDACQACQkfHyYGAAkDAAAA.Gallethline:BAABLgAECn8ZAAISAAYJYQIoTwBlAAASAAYJYQIoTwBlAAAAAA==.Garault:BAAALgAFFAIJBAAAAA==.Gavered:BAAALgADCgIJAgAAAA==.',
Ge='Gekoni:BAACLgAFFH8FAAIHAAIJagPhEwBOAAAHAAIJagPhEwBOAAAuAAQKfxoAAgcACQmfCmQlAN0AAAcACQmfCmQlAN0AAAAA.Genna:BAAALgADCgEJAQAAAA==.Geodari:BAAALgAECgkJAgAAAA==.Geodin:BAAALgAECgYJDgAAAA==.Geonon:BAABLgAECn8rAAILAAkJdw1HYgC0AQALAAkJdw1HYgC0AQAAAA==.Georgemoyd:BAAALgADCgkJCwAAAA==.',
Gh='Ghormehsubzi:BAAALgAECgEJAQAAAA==.',
Gi='Girthybeam:BAAALgAECgUJDAAAAA==.',
Gl='Glandrien:BAAALgAECgMJAwAAAA==.Glazar:BAAALgADCgkJDgAAAA==.Gloomshak:BAAALgAECgMJAgAAAA==.Glowclaws:BAAALgADCgQJAwAAAA==.Glowpwr:BAAALgADCgMJAwAAAA==.',
Go='Gobblerella:BAAALgADCgMJAwAAAA==.Gobeullin:BAAALgAFFAEJAQAAAA==.Goonthergg:BAAALgADCgkJEAAAAA==.Gothmog:BAAALgADCgMJAwAAAA==.',
Gr='Graytonson:BAAALgAECgEJAQAAAA==.Greenhills:BAAALgADCgIJAgAAAA==.Greenlocks:BAAALgADCgIJAgABLgAFFAEJAQAGAAAAAA==.Greenrånger:BAAALgAECgQJCwAAAA==.Greybush:BAABLgAECn8YAAMLAAYJChLypQAsAQALAAYJERHypQAsAQAlAAIJqA4KDgBnAAAAAA==.Griffithw:BAAALgADCgYJCwAAAA==.Grija:BAAALgAFFAYJAQAAAA==.Grimarder:BAAALgAECgYJBAAAAA==.Grizzlettz:BAAALgAECgEJAQAAAA==.Grombrindil:BAAALgAECgUJBgABLgAECggJHgAWANQMAA==.Grullander:BAABLgAECn8wAAIhAAkJ2BmKFwCBAgAhAAkJ2BmKFwCBAgABLgAFFAMJBAAGAAAAAA==.Grullandur:BAAALgAECgQJBAABLgAFFAMJBAAGAAAAAA==.',
Gu='Guideau:BAAALgAECgEJAQAAAA==.Guiguiie:BAAALgADCgcJBwAAAA==.Gusthemighty:BAAALgADCgEJAQAAAA==.',
['Gó']='Gólden:BAAALgADCgYJBgAAAA==.',
Ha='Hahacx:BAACLgAFFH8CAAIPAAIJjxeBjABEAAAPAAIJjxeBjABEAAAuAAQKfxkAAg8ACAmdIVsSAOwCAA8ACAmdIVsSAOwCAAAA.Halama:BAAALgADCgcJDAAAAA==.Halazzì:BAAALgAECgMJAwAAAA==.Haleon:BAAALgAECgIJAgAAAA==.Haraharotou:BAAALgAECgMJBgAAAA==.Hardyhar:BAAALgADCgMJBAAAAA==.',
He='Hebrews:BAAALgADCgYJBgAAAA==.Helane:BAAALgAECgcJCwAAAA==.Herkharu:BAABLgAECn8oAAITAAkJ9BRoHQDpAQATAAkJ9BRoHQDpAQAAAA==.Hermionee:BAAALgAECgUJDAAAAA==.',
Hi='Himjongun:BAABLgAECn8bAAMSAAYJ1g+yLABkAQASAAYJPQ+yLABkAQAPAAYJqwkQoQDTAAAAAA==.',
Ho='Hobbitdemon:BAAALgAECgQJBAAAAA==.Hobbitdruid:BAABLgAECn8iAAMQAAcJ8BU1HwBBAQAQAAYJZBY1HwBBAQAEAAcJ5AW0eADDAAAAAA==.Hobbitlight:BAAALgAECgcJDgAAAA==.Hobbitpriest:BAAALgADCgUJBQAAAA==.Hobbitvoid:BAAALgAECgEJAQAAAA==.Holydagoon:BAAALgADCgYJBgABLgAFFAcJFgAaAGkZAA==.Hoother:BAACLgAFFH8PAAIEAAUJrRlIGACKAQAEAAUJrRlIGACKAQAuAAQKfxQAAgQACAmdG8IWAIgCAAQACAmdG8IWAIgCAAAA.Hoppingmuff:BAAALgADCgcJDQAAAA==.',
Hu='Humble:BAAALgADCgEJAQAAAA==.Hunia:BAABLgAECn8UAAIIAAcJ/wlwjwATAQAIAAcJ/wlwjwATAQAAAA==.Huntagrizz:BAAALgAECgQJBAAAAA==.Huntieluis:BAAALgAECgQJBAAAAA==.Hurndredd:BAAALgAECgIJAwAAAA==.Huuh:BAAALgADCgMJBgAAAA==.',
Hy='Hystericc:BAAALgAECgYJCQAAAA==.',
['Hé']='Héboric:BAABLgAECn8YAAIKAAgJZBfFHQAKAgAKAAgJZBfFHQAKAgAAAA==.',
['Hõ']='Hõlycow:BAAALgAECgcJDgAAAA==.',
Id='Idkno:BAAALgADCgEJAgAAAA==.Idolon:BAAALgADCggJHQAAAA==.',
Ik='Ikala:BAAALgAECgQJBAAAAA==.Ikashi:BAAALgADCgEJAQAAAA==.Ikodiwa:BAAALgAECgYJEQAAAA==.',
Il='Ilisa:BAAALgADCgMJAwAAAA==.Ilrion:BAABLgAECn8cAAMgAAkJtgvGOQAdAQAgAAcJbAzGOQAdAQAEAAYJCQeFiQDCAAAAAA==.',
In='Indravax:BAAALgAECgMJBQAAAA==.Inferno:BAAALgAECgEJAwAAAA==.',
Is='Iseehot:BAABLgAECn8hAAILAAYJah5ThABoAQALAAYJah5ThABoAQAAAA==.',
It='Itschubbzdru:BAAALgAFFAEJAQAAAA==.',
Iv='Ivantis:BAABLgAECn8ZAAMHAAcJDwiBLgCiAAAHAAcJmASBLgCiAAADAAMJ3w3JFAGQAAAAAA==.Ivie:BAABLgAECn8eAAMEAAgJUhNlPACZAQAEAAgJUhNlPACZAQAgAAIJwA0mbwBcAAAAAA==.Ivieenfuego:BAACLgAFFH8OAAIaAAMJ+QDVUwBtAAAaAAMJ+QDVUwBtAAAuAAQKfzoAAhoACQliBcZHAAEBABoACQliBcZHAAEBAAAA.',
Ja='Jackjack:BAABLgAFFH8HAAIUAAQJJQxLbQAYAQAUAAQJJQxLbQAYAQAAAA==.Jackjackk:BAABLgAFFH8GAAIOAAMJXwS2QQB5AAAOAAMJXwS2QQB5AAABLgAFFAQJBwAUACUMAA==.Jadednurse:BAABLgAECn8VAAMkAAYJVhb/MgAtAQAkAAYJVhb/MgAtAQAcAAQJVAcbUgCkAAAAAA==.Jakisormjr:BAAALgADCgIJAgAAAA==.Jalanii:BAABLgAECn8qAAIDAAkJpBLkPQADAgADAAkJpBLkPQADAgAAAA==.Janjor:BAACLgAFFH8SAAMTAAUJNxM9IAAQAQATAAQJNxM9IAAQAQAhAAIJIw4jXAB8AAAuAAQKfzQAAxMACQkuHk8QAGYCABMACQkuHk8QAGYCACEABAn2G0JZAEIBAAAA.Janjorski:BAAALgADCgQJBAAAAA==.Jayrior:BAAALgADCgcJCwAAAA==.',
Je='Jehlock:BAAALgAECgUJCgAAAA==.Jehvoker:BAAALgAECggJEwABLgAECgUJCgAGAAAAAA==.Jerghal:BAAALgAECgYJEAAAAA==.Jesthos:BAAALgAECgcJAgABLgAECgcJCwAGAAAAAA==.Jettian:BAABLgAECn8nAAIUAAcJDRIXdwBtAQAUAAcJDRIXdwBtAQAAAA==.',
Ji='Jinu:BAAALgADCgIJAgAAAA==.',
Jj='Jjdruid:BAAALgAECgEJAQAAAA==.',
Jo='Jockwork:BAAALgAECgQJDQAAAA==.Jokeer:BAAALgAECgUJDgAAAA==.Jolene:BAABLgAECn8aAAIgAAcJbgqNSQDXAAAgAAcJbgqNSQDXAAAAAA==.Jollygreene:BAABLgAECn8eAAIgAAcJgAVSUQC5AAAgAAcJgAVSUQC5AAAAAA==.Joyina:BAAALgADCgkJIgAAAA==.',
Ju='Juggærnaut:BAAALgAECgQJBwAAAA==.Junjie:BAAALgAECgMJAwAAAA==.Justicee:BAAALgAECgQJCAABLgAECggJDAAGAAAAAA==.',
Jx='Jxy:BAAALgAECgUJCQABLgAFFAgJKQAPAEgfAA==.',
Ka='Kachess:BAAALgADCgkJCQAAAA==.Kaddar:BAAALgADCgYJBgAAAA==.Kahri:BAABLgAECn8hAAQQAAgJDBsdCwAfAgAQAAgJDBsdCwAfAgAmAAUJxBMaIgDkAAAEAAEJiAWj5gAhAAAAAA==.Kakali:BAAALgAECgcJCAAAAA==.Kalend:BAAALgAECgMJAwAAAA==.Karametra:BAAALgAECgEJAgAAAA==.Karlager:BAABLgAECn8eAAIWAAgJ1AwXLwA/AQAWAAgJ1AwXLwA/AQAAAA==.Karlain:BAAALgAECgYJDQAAAA==.Karldun:BAAALgADCggJCAABLgAECggJHgAWANQMAA==.Kasaide:BAAALgADCgcJDQABLgAECgkJNQAFAPgUAA==.Kasmir:BAABLgAECn81AAIFAAkJ+BTmKwAjAgAFAAkJ+BTmKwAjAgAAAA==.Kassella:BAAALgADCgMJAwAAAA==.Katia:BAAALgADCgUJBwAAAA==.Kaylana:BAAALgADCgEJAQAAAA==.Kazoo:BAAALgAECgQJBAABLgAFFAYJGQAcAOIWAA==.',
Ke='Keeflo:BAAALgADCgkJEgAAAA==.Kelisii:BAAALgAFFAMJBAAAAA==.Keloenivas:BAAALgADCggJEQAAAA==.Kelomage:BAAALgAECgEJAQAAAA==.Ketaza:BAAALgAECgEJAQAAAA==.Keyash:BAAALgADCgIJAgAAAA==.',
Kh='Khyle:BAAALgADCgEJAQABLgADCgcJEAAGAAAAAA==.',
Ki='Kibblebits:BAABLgAECn8aAAIgAAcJbwPwXQCPAAAgAAcJbwPwXQCPAAAAAA==.Kijanajr:BAAALgAECgIJAgAAAA==.Kitch:BAAALgAECgcJEAAAAA==.Kitheros:BAAALgADCgcJBwAAAA==.Kittun:BAAALgADCgEJAQAAAA==.',
Kl='Klay:BAABLgAECn89AAQZAAkJaCZ/AAB1AwAZAAkJaCZ/AAB1AwACAAMJug1pNABgAAABAAIJtQKSngBGAAAAAA==.Klutch:BAAALgADCgIJAgAAAA==.',
Km='Kmarti:BAECLgAFFH8TAAIPAAUJaRECQwAPAQAPAAUJaRECQwAPAQAuAAQKfyYAAw8ACQklHmUhAIkCAA8ACQklHmUhAIkCABIAAgn/CwFgAGIAAAAA.',
Ko='Koivath:BAAALgADCgkJEQAAAA==.Konradevoker:BAAALgAFFAEJAgABLgAECgkJKwAFAFUeAA==.Konradlock:BAABLgAECn8rAAMFAAkJVR6YBgBVAwAFAAkJVR6YBgBVAwANAAIJVxk5TQCGAAAAAA==.Konradrogue:BAABLgAECn8xAAMnAAkJuB6tAABiAwAnAAkJoR6tAABiAwAVAAcJYxraHQAPAgABLgAECgkJKwAFAFUeAA==.Konradwar:BAABLgAECn8XAAMCAAYJNx79EgBzAQACAAYJZhj9EgBzAQABAAQJpRbCbgD8AAABLgAECgkJKwAFAFUeAA==.Koros:BAAALgAECgQJBAAAAA==.Kosmicknight:BAABLgAECn8jAAMUAAkJ9BS6VAC/AQAUAAgJ7xW6VAC/AQAiAAIJPw3kRgBlAAAAAA==.',
Kr='Krathös:BAAALgAECgcJEwAAAA==.Krimzin:BAAALgAECgEJAgABLgAFFAUJGgAIADAhAA==.Kromak:BAAALgAECgQJBAAAAA==.Kryesta:BAAALgADCgMJAwAAAA==.',
Ku='Kunfoopizza:BAAALgAECgQJCQAAAA==.Kuulibah:BAAALgADCgEJAQABLgADCgMJAwAGAAAAAA==.Kuulibarr:BAAALgADCgMJAwAAAA==.',
Kw='Kwarr:BAACLgAFFH8TAAIhAAUJaxFJJgA0AQAhAAUJaxFJJgA0AQAuAAQKfyIAAiEACAnlHxMSALICACEACAnlHxMSALICAAEuAAUUBgkWABkAnhsA.',
Ky='Kyaila:BAAALgADCgEJAQAAAA==.Kynaragon:BAABLgAECn8lAAMgAAcJfSaVGABEAgAgAAYJZSaVGABEAgAEAAQJ0CSqYwAmAQABLgAFFAcJBgAEACwfAA==.Kyrimmon:BAAALgAECgEJAQAAAA==.',
La='Laelìa:BAAALgAECgEJAQAAAA==.Lalii:BAAALgAECgEJAwAAAA==.Lallypop:BAABLgAECn8VAAILAAcJTg8gkABSAQALAAcJTg8gkABSAQAAAA==.Lammoth:BAAALgAECgEJAgAAAA==.Lanthein:BAAALgAECgEJAQABLgAFFAcJFgAaAGkZAA==.Laraela:BAAALgADCgEJAQAAAA==.Largehusband:BAAALgAECgEJAQAAAA==.Larkindas:BAAALgAECgMJBAAAAA==.Layil:BAAALgADCgYJBwAAAA==.',
Le='Leafu:BAABLgAECn8UAAMJAAUJEhtnQgDoAAAJAAMJ5BpnQgDoAAAOAAUJ9AnCbQCxAAABLgAECggJKAAdAGwdAA==.Leasin:BAABLgAECn8oAAIdAAgJbB1tEwAuAgAdAAgJbB1tEwAuAgAAAA==.Leathle:BAAALgADCgkJEAAAAA==.Leepa:BAAALgAECgcJDgAAAA==.Leesta:BAAALgAECgEJAgAAAA==.Lepp:BAAALgAECgEJAQAAAA==.Lexslaner:BAAALgADCgYJCQAAAA==.',
Li='Lighthusk:BAABLgAECn8cAAMkAAkJKx/9BwDgAgAkAAkJKx/9BwDgAgAdAAQJMwaVYACGAAABLgAECgkJHAAkACsfAA==.Lightreaper:BAAALgAECgEJAQAAAA==.Likeans:BAAALgAECgEJAQAAAA==.Liliauna:BAABLgAECn8uAAIFAAkJpxUIMgALAgAFAAkJpxUIMgALAgAAAA==.Lilibejeane:BAAALgAECgYJCAABLgAECgkJLQASAFIUAA==.Lilithalen:BAACLgAFFH8TAAIkAAUJ0hF5DQBdAQAkAAUJ0hF5DQBdAQAuAAQKfzEAAiQACQlOGegVAC0CACQACQlOGegVAC0CAAAA.Lilmymy:BAAALgAECgIJAgAAAA==.Lilshimer:BAABLgAECn8YAAMFAAcJTRieVgDEAQAFAAcJTRieVgDEAQAMAAIJdQMoIQBtAAAAAA==.Lilsquirtboy:BAACLgAFFH8XAAIUAAQJ1SX4IQDCAQAUAAQJ1SX4IQDCAQAuAAQKfzMAAxQACQnzI3gKABQDABQACQnzI3gKABQDACIAAQmZCcdNABsAAAAA.Linithara:BAAALgAECgUJBQABLgAFFAUJEwAkANIRAA==.Litterling:BAAALgAECgcJDAAAAA==.Lizardbird:BAAALgAECgQJBwAAAA==.Lizzi:BAAALgADCgcJBgAAAA==.',
Lo='Lockersz:BAAALgAECgQJCgABLgAFFAUJCQAYAAMNAA==.Lockitt:BAABLgAECn8dAAIFAAkJ8w8mXQCxAQAFAAkJ8w8mXQCxAQAAAA==.Loram:BAAALgAECgEJAQAAAA==.Lostangel:BAAALgADCgkJCAAAAA==.Lostgrip:BAAALgAECgUJCAAAAA==.',
Lu='Luckiecharm:BAAALgADCgUJBQAAAA==.Lucthedk:BAABLgAECn8aAAIUAAYJThLxpgAYAQAUAAYJThLxpgAYAQAAAA==.Luk:BAAALgADCgYJBgAAAA==.Lukis:BAAALgAECgEJAQAAAA==.Lumario:BAAALgADCgEJAQAAAA==.Lunarpriest:BAAALgAECgEJAQAAAA==.Lunitari:BAAALgAECgYJBgAAAA==.Lunkbeck:BAAALgAECgcJEQAAAA==.Luva:BAAALgADCgcJEQAAAA==.Luxriel:BAAALgAECgQJBgAAAA==.',
Ly='Lyio:BAAALgAECgUJDAAAAA==.',
Ma='Madmandeath:BAAALgADCgQJAwAAAA==.Magicmegan:BAAALgAECgEJAgABLgAFFAEJAQAGAAAAAA==.Mahlanas:BAAALgAECgYJDgAAAA==.Maki:BAABLgAFFH8MAAIUAAMJsRaEiQDkAAAUAAMJsRaEiQDkAAAAAA==.Maladin:BAABLgAECn8aAAMHAAkJaAnBHwAJAQAHAAgJqwnBHwAJAQADAAQJVgRHFgGOAAAAAA==.Malvean:BAAALgADCgcJCgAAAA==.Mamajoy:BAAALgADCgMJBgAAAA==.Maravilla:BAABLgAECn8WAAIQAAgJhQ0sKQD9AAAQAAgJhQ0sKQD9AAAAAA==.Marceline:BAABLgAECn8ZAAIIAAkJwhfYHwBdAgAIAAkJwhfYHwBdAgAAAA==.Markuspapa:BAAALgAECgQJBAABLgAFFAYJGQAcAOIWAA==.Marlowe:BAAALgAECgcJDQAAAA==.Marremer:BAABLgAECn8ZAAMiAAgJOA0fJAAgAQAiAAUJnhMfJAAgAQAjAAgJzwPSHwC8AAAAAA==.',
Mc='Mckicky:BAAALgAECgYJDwAAAA==.',
Me='Mechafire:BAAALgADCgYJBgAAAA==.Melanius:BAACLgAFFH8RAAIeAAUJaBV+EgBUAQAeAAUJaBV+EgBUAQAuAAQKfzcAAx4ACQkaJdkAALADAB4ACQkaJdkAALADAB8AAQkeD+gjADUAAAAA.Melliex:BAAALgADCgMJBgAAAA==.Melodras:BAABLgAECn8eAAMkAAgJrhKbKAB0AQAkAAgJrhKbKAB0AQAcAAIJkgZqTgBXAAAAAA==.Memelord:BAAALgAECgQJCgAAAA==.Merce:BAAALgADCgEJAQAAAA==.Metalock:BAAALgADCgcJCwAAAA==.Mewalina:BAAALgADCgQJBAAAAA==.',
Mi='Mirajen:BAAALgADCgMJAwAAAA==.Mirukoo:BAAALgAECgQJBAAAAA==.Misclick:BAAALgADCgQJBAAAAA==.Misconduct:BAACLgAFFH8JAAISAAMJgRCYFwDJAAASAAMJgRCYFwDJAAAuAAQKfyUAAhIACQkOILwFANUCABIACQkOILwFANUCAAAA.Missile:BAAALgAECgIJAgAAAA==.Mistytim:BAAALgAECgQJBAABLgAECggJGAAKAGQXAA==.Mistywaters:BAAALgAECgEJAgAAAA==.Mittyy:BAAALgADCgYJBwAAAA==.',
Mo='Moomist:BAAALgAECgcJDwAAAA==.Moonwrath:BAAALgAFFAEJAQAAAA==.Moosifer:BAAALgAECgEJAQAAAA==.Mornintreant:BAAALgADCgMJAwAAAA==.Morukhai:BAAALgADCgcJCAAAAA==.Mosshorn:BAAALgADCgEJAQAAAA==.Mousekewitzk:BAAALgAECgQJAwAAAA==.Movarth:BAAALgADCgkJCQAAAA==.',
Mu='Mujer:BAAALgAECgEJAQAAAA==.Mungas:BAAALgADCgUJBgAAAA==.Murlloc:BAAALgADCgcJBgAAAA==.',
My='Myrathia:BAABLgAFFH8GAAIEAAIJmARNXABbAAAEAAIJmARNXABbAAAAAA==.Myrcella:BAAALgAECgQJBQAAAA==.',
['Má']='Máximodécimo:BAAALgAECgMJDAAAAA==.',
Na='Nahemah:BAAALgAECgIJAwABLgAECggJFAAPAI8WAA==.Nahtan:BAABLgAECn8uAAIIAAgJuBVhPgDdAQAIAAgJuBVhPgDdAQAAAA==.Nahwe:BAAALgADCgUJBQAAAA==.Narrsul:BAABLgAECn8XAAIFAAYJ6RJycwB4AQAFAAYJ6RJycwB4AQAAAA==.Nattyg:BAAALgAECgYJEAAAAA==.Naves:BAAALgADCgYJCAAAAA==.',
Ne='Nebbia:BAAALgAECgEJAwAAAA==.Nekamsi:BAAALgAECgEJAQAAAA==.Nereza:BAAALgADCgUJDAAAAA==.Nevermorte:BAAALgAECgYJBgAAAA==.',
Nf='Nfggolden:BAAALgAECgcJAwAAAA==.',
Ni='Nightforday:BAABLgAECn9UAAIUAAkJDyBWDwDpAgAUAAkJDyBWDwDpAgAAAA==.Niko:BAAALgAECgQJDQAAAA==.Nineve:BAAALgADCgIJAgABLgADCgkJCwAGAAAAAA==.',
No='Noknani:BAAALgADCgUJBgAAAA==.Nokx:BAAALgAECgEJAQAAAA==.Nool:BAAALgADCgcJCQAAAA==.Norch:BAAALgADCgMJBAAAAA==.Nostranova:BAAALgAECgEJAQAAAA==.Novà:BAAALgADCgMJAwAAAA==.',
Nu='Nube:BAAALgADCggJCAAAAA==.',
Ny='Nyriand:BAAALgADCgQJBAAAAA==.Nyxiia:BAAALgADCgIJAgAAAA==.',
Ob='Obalon:BAAALgAECgEJAQAAAA==.',
Oe='Oedipuss:BAAALgADCgUJBQABLgADCgYJCAAGAAAAAA==.',
Og='Ogora:BAAALgADCgIJAgAAAA==.',
Oh='Ohkayboomer:BAABLgAFFH8GAAMEAAQJmgunSQCLAAAEAAMJjQOnSQCLAAAgAAIJ2QHiQgBNAAAAAA==.Ohkaylocker:BAAALgAECggJDgAAAA==.',
Ok='Okktral:BAAALgAFFAIJAgAAAA==.Oktraal:BAAALgAECgEJAQABLgAFFAIJAgAGAAAAAA==.',
Oo='Oontanx:BAAALgADCgcJCQAAAA==.Ooups:BAABLgAECn8gAAIJAAgJcBR4IQCUAQAJAAgJcBR4IQCUAQAAAA==.',
Op='Ophysia:BAABLgAECn8mAAIDAAgJQB2vMgArAgADAAgJQB2vMgArAgAAAA==.',
Or='Orangecage:BAABLgAECn9NAQMgAAkJqyZfAACQAwAgAAkJqyZfAACQAwAEAAIJfwYmswBeAAAAAA==.Orkcansas:BAAALgAFFAEJAQAAAA==.Orong:BAAALgAECgMJBAAAAA==.',
Os='Osla:BAAALgAECgkJEAAAAA==.Osrsfemale:BAAALgAECgIJAgAAAA==.',
Ov='Overlooker:BAAALgAECgQJBwAAAA==.',
Ox='Oxazine:BAACLgAFFH8HAAITAAMJHQ2mMgC2AAATAAMJHQ2mMgC2AAAuAAQKfykAAxMACQlKGU0WACYCABMACQlKGU0WACYCACEABQmOA2WeAHwAAAAA.',
Pa='Paapineau:BAABLgAECn8jAAInAAgJ2QhtDgA0AQAnAAgJ2QhtDgA0AQAAAA==.Packel:BAAALgADCgEJAQABLgAECgkJMQAQAHETAA==.Packs:BAAALgAECgEJAQABLgAECgkJMQAQAHETAA==.Palladias:BAAALgAECgQJBgAAAA==.Pally:BAAALgADCgIJAgAAAA==.Partysnaxx:BAAALgAECgEJAQAAAA==.',
Pc='Pcm:BAAALgAFFAEJAQABLgAFFAEJAQAGAAAAAA==.',
Pe='Peefmajeef:BAAALgADCgIJAgAAAA==.Peony:BAAALgADCgQJBAAAAA==.Pepperjack:BAAALgAECgQJBwAAAA==.Petshellkek:BAACLgAFFH8ZAAMUAAcJxSI6BQCuAQAUAAcJxSI6BQCuAQAjAAEJhRfLHwBQAAAuAAQKfxcAAhQACAktI34UAAADABQACAktI34UAAADAAAA.Pewpeew:BAAALgAECgUJDQAAAA==.',
Ph='Phantomclone:BAABLgAECn8UAAIWAAYJYR7LLgBBAQAWAAYJYR7LLgBBAQAAAA==.Phantomghoul:BAAALgADCgEJAQAAAA==.Phantomwar:BAAALgAECgIJAgAAAA==.Phantomzz:BAAALgAECgEJAQAAAA==.Phaté:BAAALgADCgEJAQAAAA==.Pheonixxwolf:BAAALgAECgYJDgAAAA==.Pherc:BAAALgADCgcJBwAAAA==.Phillyblunt:BAABLgAECn8aAAMhAAcJURNHMQDBAQAhAAcJURNHMQDBAQATAAEJDQcjiwAtAAAAAA==.Philomena:BAAALgADCgEJAQAAAA==.Phløw:BAAALgADCgUJDwAAAA==.Phðéñîx:BAAALgADCgUJBQAAAA==.',
Pi='Picaroxy:BAAALgADCgUJBQAAAA==.Piyo:BAAALgAECgcJCgABLgAECgkJMQAQAHETAA==.Piyoo:BAAALgADCgUJBQABLgAECgkJMQAQAHETAA==.',
Pl='Plaguekitten:BAAALgAECgEJAQAAAA==.',
Po='Poisonblade:BAAALgAECgEJAgAAAA==.Pollidi:BAAALgAFFAEJAQAAAA==.Poolius:BAABLgAECn8UAAILAAQJdgPQGQFxAAALAAQJdgPQGQFxAAAAAA==.Popadot:BAAALgAECgkJBQAAAA==.Porfinne:BAAALgAECgMJBwAAAA==.',
Pr='Praedor:BAAALgADCgUJBQAAAA==.Preza:BAAALgADCgIJAgAAAA==.Priestymon:BAACLgAFFH8HAAIcAAIJ3htfNQCUAAAcAAIJ3htfNQCUAAAuAAQKfyYAAxwACAkOH4IKAJECABwACAkOH4IKAJECAB0ABQnxFKJAAAUBAAEuAAUUBgkVAAEACR8A.Prober:BAAALgADCgUJBQAAAA==.Producer:BAAALgAECgEJAQAAAA==.Protato:BAAALgAECgYJCwAAAA==.Prowaifu:BAAALgAECgYJDAAAAA==.Prowess:BAAALgADCggJFAAAAA==.Prîestitute:BAAALgADCgYJCQAAAA==.',
Pu='Purger:BAAALgADCgYJCgAAAA==.Pussinbooger:BAAALgAECgEJAQAAAA==.Puyo:BAABLgAECn8xAAIQAAkJcRN/EwCqAQAQAAkJcRN/EwCqAQAAAA==.Puyyoo:BAAALgADCgcJDwABLgAECgkJMQAQAHETAA==.',
Pw='Pwarr:BAACLgAFFH8WAAIZAAYJnhu3CQB6AQAZAAYJnhu3CQB6AQAuAAQKfywAAxkACAmPIL0KAGUCABkABwmWIr0KAGUCAAIACAm1Ew4VAKsBAAAA.',
Py='Pyrofox:BAAALgADCgEJAQAAAA==.',
Qu='Quackichan:BAAALgAECgYJBgAAAA==.',
Qw='Qwarr:BAACLgAFFH8eAAMaAAUJdRSGKQAPAQAaAAUJdRSGKQAPAQAfAAIJWQnfBgChAAAuAAQKf0EABBoACQnWInkGAO0CABoACQnWInkGAO0CAB8ABglCHu8PAN0BAB4ABQkpCgMiANYAAAEuAAUUBgkWABkAnhsA.',
Ra='Raeljin:BAAALgAECgkJBgAAAA==.Rafoen:BAABLgAFFH8FAAIVAAIJ2hP8MACOAAAVAAIJ2hP8MACOAAAAAA==.Rakrur:BAAALgADCgEJAQAAAA==.Ramsay:BAAALgAECgMJAwAAAA==.Ranee:BAAALgAECgMJBAAAAA==.Rathorn:BAAALgAECgUJBQAAAA==.Ravnur:BAAALgADCgkJCQAAAA==.Rawrr:BAAALgAECgEJAQAAAA==.Raxsan:BAAALgAFFAMJBAAAAA==.Raydanbalor:BAAALgAECgUJBQABLgAECggJGQAiADgNAA==.Rayenera:BAAALgAECgEJAQAAAA==.Rayennagrom:BAABLgAECn8bAAMlAAcJpQZkCQDXAAAlAAcJpQZkCQDXAAALAAEJAADNegEAAAAAAA==.Razkko:BAAALgADCgUJBQAAAA==.',
Rd='Rdru:BAAALgADCgcJBwABLgAECgYJEAAGAAAAAA==.',
Re='Redpumpkin:BAAALgADCgMJAwAAAA==.Redsonja:BAAALgADCgcJDQAAAA==.Rel:BAAALgADCgYJBgAAAA==.Reneana:BAAALgAECgUJAgAAAA==.Respectisluv:BAABLgAECn8mAAIXAAgJfBAzHQCuAQAXAAgJfBAzHQCuAQAAAA==.Restbo:BAABLgAFFH8GAAIhAAMJPx99LwANAQAhAAMJPx99LwANAQAAAA==.Rexcor:BAAALgAECgQJDgAAAA==.',
Rh='Rhulad:BAAALgADCggJCAAAAA==.',
Ri='Riaeline:BAAALgAECgQJBgAAAA==.Richardluis:BAAALgAECgYJCwAAAA==.Rinehardtt:BAAALgAFFAIJAgAAAA==.Ripchan:BAAALgADCgIJAgABLgAFFAYJGQAhAGwSAA==.Ripchi:BAAALgAECgcJBwABLgAFFAYJGQAhAGwSAA==.Ripcurrent:BAAALgAECgUJBQAAAA==.Ripheals:BAACLgAFFH8ZAAMhAAYJbBIlGwB1AQAhAAYJbBIlGwB1AQATAAEJFggdUAA6AAAuAAQKfzcAAyEACQkVHU0eAE8CACEACQkVHU0eAE8CABMABQlUGhlBAEUBAAAA.Riplee:BAAALgADCgYJCwABLgAFFAYJGQAhAGwSAA==.Rit:BAAALgAECgIJAgAAAA==.Rivër:BAABLgAECn8YAAIDAAkJqxv6PwAmAgADAAkJqxv6PwAmAgAAAA==.',
Ro='Robbell:BAABLgAECn8bAAIIAAgJaxkLIABFAgAIAAgJaxkLIABFAgAAAA==.Rockd:BAAALgAECgcJCwAAAA==.Rogueflame:BAAALgAECgcJDwAAAA==.Rootsie:BAABLgAECn8dAAINAAcJgQvvFAD1AAANAAcJgQvvFAD1AAAAAA==.Roselynn:BAABLgAECn8tAAIEAAkJgBvdDwC5AgAEAAkJgBvdDwC5AgAAAA==.',
Rs='Rsolbes:BAAALgADCgUJBQAAAA==.',
Ru='Ruerl:BAABLgAECn8YAAMHAAkJ8g0UIwDvAAAHAAYJGwoUIwDvAAADAAkJPgq/zgDnAAAAAA==.Ruffandready:BAAALgADCgMJAwAAAA==.Rumblies:BAABLgAECn8WAAIOAAgJCxrLHgAPAgAOAAgJCxrLHgAPAgAAAA==.Runetusk:BAAALgADCgEJAQABLgAECgYJDQAGAAAAAA==.Rungin:BAAALgADCgEJAQAAAA==.Russopp:BAAALgADCgEJAQAAAA==.',
Sa='Saars:BAAALgADCgYJBgAAAA==.Samchan:BAAALgAECgcJEwAAAA==.Sanatharia:BAAALgAECgYJDAAAAA==.Saneatey:BAAALgAECgUJCwAAAA==.Sassibelle:BAAALgAECgUJBQAAAA==.Satanskidney:BAAALgAECgQJBQAAAA==.Sathenset:BAACLgAFFH8WAAIaAAcJaRniDgDtAQAaAAcJaRniDgDtAQAuAAQKfxUAAx8ACAnLGFARAMoBAB8ABwmsFlARAMoBABoABAmrEjlDANQAAAAA.Savara:BAAALgAECgMJAwABLgAFFAcJFgAaAGkZAA==.',
Sc='Scandium:BAACLgAFFH8FAAIMAAMJgQRKCgDEAAAMAAMJgQRKCgDEAAAuAAQKfzIAAgwACQkqIN4CAIkCAAwACQkqIN4CAIkCAAAA.Scrembiblion:BAABLgAECn8wAAMLAAkJLiJhDgACAwALAAkJLiJhDgACAwAbAAIJjB6WCwC0AAAAAA==.',
Sd='Sdhoscillate:BAAALgAFFAEJAQAAAA==.',
Se='Seagulpunchr:BAAALgADCgYJCgAAAA==.Seesh:BAACLgAFFH8KAAIBAAQJLiD1BgB+AQABAAQJLiD1BgB+AQAuAAQKfxgAAgEACQnSJBQDAH8DAAEACQnSJBQDAH8DAAAA.Seidr:BAAALgAECgYJBwAAAA==.Senseitional:BAABLgAECn8aAAMOAAgJ2xltFgBTAgAOAAgJ2xltFgBTAgAJAAgJ+BZkGADcAQABLgAECgkJMAAFAGcaAA==.Sentarr:BAABLgAFFH8VAAIZAAUJrSGTDQBBAQAZAAUJrSGTDQBBAQAAAA==.Septhera:BAAALgAFFAEJAgAAAA==.',
Sh='Shadewither:BAAALgADCgQJBAAAAA==.Shadey:BAAALgAECgEJAQAAAA==.Shadeyheals:BAAALgAECggJEQAAAA==.Shadowxcraft:BAAALgAECgcJDQAAAA==.Shadrelin:BAAALgADCgEJAgAAAA==.Shadygnome:BAAALgAECgYJBAAAAA==.Shaqler:BAAALgAECgMJBAAAAA==.Shecks:BAAALgADCgcJCAAAAA==.Shelandria:BAAALgAECgQJBgAAAA==.Sherwild:BAABLgAECn8YAAIEAAgJxyHwCgDqAgAEAAgJxyHwCgDqAgAAAA==.Shinara:BAABLgAECn8mAAIVAAgJ9RixEwD5AQAVAAgJ9RixEwD5AQAAAA==.Shiverchill:BAAALgAECgcJCQAAAA==.Shizznoint:BAAALgADCgMJAwAAAA==.Shnipishnap:BAABLgAECn+tAAMhAAkJHiPWAACgAwAhAAkJHiPWAACgAwATAAkJviZHAACOAwAAAA==.Shroomjuicee:BAABLgAECn85AAIcAAkJxBu5CADfAgAcAAkJxBu5CADfAgAAAA==.Shyi:BAAALgADCgYJBgAAAA==.Shìlo:BAAALgAECgUJBwAAAA==.Shìlò:BAAALgAECgQJBAAAAA==.',
Si='Sindaemon:BAACLgAFFH8HAAIPAAMJdRuJIwCzAAAPAAMJdRuJIwCzAAAuAAQKfyMAAg8ACAn2IWQUAN0CAA8ACAn2IWQUAN0CAAAA.Sindrina:BAAALgAECgYJBwAAAA==.',
Sk='Skedaddle:BAAALgAECgQJBgAAAA==.Skelstone:BAAALgADCgYJBgAAAA==.Skädoosh:BAAALgAECgcJDgAAAA==.',
Sl='Slapshappy:BAABLgAECn8zAAIDAAgJvRmKRADuAQADAAgJvRmKRADuAQAAAA==.Sloptop:BAAALgAECgMJAwAAAA==.Slowfall:BAAALgADCgcJCwAAAA==.',
Sm='Smithssinger:BAAALgAECgUJBQAAAA==.Smokin:BAAALgAECgYJDwAAAA==.Smoothg:BAAALgAECgMJAwAAAA==.',
Sn='Snowjor:BAAALgADCgEJAQAAAA==.Snyx:BAAALgADCgUJBQAAAA==.',
So='Solaríus:BAAALgADCgMJAwAAAA==.Soldanas:BAAALgADCgEJAQAAAA==.Solomus:BAAALgAECgUJDgAAAA==.Sorceroid:BAAALgADCgIJAgAAAA==.Soteria:BAAALgAECgEJAQAAAA==.',
Sp='Spheaddin:BAAALgAECgEJAQAAAA==.Spiritbomb:BAABLgAECn8lAAIPAAkJsRrvIABFAgAPAAkJsRrvIABFAgAAAA==.Spytime:BAAALgAECgcJDQAAAA==.',
Ss='Ssjchezzy:BAAALgAECgcJDgAAAA==.Ssmeltn:BAAALgAECgYJDQAAAA==.',
St='Staranaria:BAAALgADCgUJBQAAAA==.Steinberg:BAAALgADCgEJAQAAAA==.Stelltrain:BAAALgAECgQJBAAAAA==.Stnaprednu:BAACLgAFFH8IAAIDAAMJIw/9aADMAAADAAMJIw/9aADMAAAuAAQKfx8AAwMACAknGvYyACoCAAMACAknGvYyACoCAAcAAQkAAJlcAAAAAAAA.Stoploss:BAAALgADCgEJAQAAAA==.Stormiee:BAABLgAECn8XAAIhAAkJ2Q48NwDFAQAhAAkJ2Q48NwDFAQABLgAECggJHgAEAFITAA==.Stormr:BAAALgAECgQJBAAAAA==.Stormroid:BAAALgAECgYJCgAAAA==.Stormxwolf:BAAALgAECgYJDQAAAA==.Strangulate:BAAALgAECgQJBQAAAA==.Stripez:BAAALgADCgUJBwAAAA==.Stumpvee:BAAALgADCgMJAwAAAA==.',
Su='Sunmx:BAABLgAFFH8MAAIBAAMJayKPHwAmAQABAAMJayKPHwAmAQAAAA==.Sunmxqwe:BAAALgAECgEJAQAAAA==.Superdark:BAAALgAECgMJBgAAAA==.Surgah:BAAALgADCgEJAQAAAA==.',
Sw='Swurves:BAABLgAFFH8FAAIDAAMJLgeXcQC6AAADAAMJLgeXcQC6AAAAAA==.',
Sy='Sybrooker:BAAALgADCgQJBQAAAA==.',
Ta='Tadpole:BAAALgAECgcJBwAAAA==.Taedrum:BAAALgAECgcJEgAAAA==.Taerror:BAACLgAFFH8XAAIkAAYJwxsmBAARAgAkAAYJwxsmBAARAgAuAAQKfzEABCQACQmyI38AAK8DACQACQmyI38AAK8DABwABAmIGE09AAoBAB0AAQktB+aHACoAAAAA.Tahkon:BAAALgAECgYJCwAAAA==.Tahmtan:BAAALgADCgcJEAAAAA==.Talegos:BAAALgAECgQJBAAAAA==.Talonfel:BAAALgADCgcJCwABLgAFFAMJEAAOAN0dAA==.Talonflight:BAAALgAECggJDwABLgAFFAMJEAAOAN0dAA==.Talonsic:BAAALgAECgQJBAABLgAFFAMJEAAOAN0dAA==.Talonstryke:BAACLgAFFH8QAAIOAAMJ3R0AKAABAQAOAAMJ3R0AKAABAQAuAAQKfz8AAg4ACQl0I1gDAHwDAA4ACQl0I1gDAHwDAAAA.Taloran:BAAALgADCgkJFAAAAA==.Talzul:BAAALgADCgMJAwAAAA==.Tanarious:BAAALgADCgQJBAAAAA==.Taytonar:BAABLgAECn8tAAIHAAcJUwpWJADkAAAHAAcJUwpWJADkAAAAAA==.',
Te='Teamocil:BAAALgAECgEJAwAAAA==.Teefa:BAAALgAECgYJCwAAAA==.Tehrror:BAAALgADCgMJAwAAAA==.Tehyra:BAAALgAECgMJAwAAAA==.Tenths:BAAALgADCgEJAQAAAA==.Terak:BAAALgAECgEJAQAAAA==.Terrisman:BAAALgAECgYJBgABLgAECgkJMAAFAGcaAA==.Testsubjectz:BAAALgAFFAUJAQAAAA==.Tevers:BAAALgADCgcJDAAAAA==.',
Th='Thane:BAAALgADCgMJAwAAAA==.Thaumium:BAAALgADCgEJAQAAAA==.Theenforcer:BAABLgAECn8hAAIDAAgJJw7EfgBmAQADAAgJJw7EfgBmAQAAAA==.Theguyfurry:BAAALgADCgcJCwAAAA==.Thidwick:BAAALgAECgYJDQABLgAECgkJMAAFAGcaAA==.Thingtwø:BAAALgAECgMJAwAAAA==.Thirdryker:BAAALgADCgIJAgAAAA==.Thistle:BAAALgAECgcJCgAAAA==.Thorissa:BAABLgAECn8YAAINAAgJzA0PEwCzAQANAAgJzA0PEwCzAQAAAA==.Thäne:BAABLgAECn8pAAIUAAcJuBPrdgBtAQAUAAcJuBPrdgBtAQAAAA==.',
Ti='Tibbzz:BAAALgAECgYJCwAAAA==.Tickletorque:BAAALgAECgcJEQABLgAFFAQJFwAUANUlAA==.Tikimon:BAAALgADCgIJAgAAAA==.Tiles:BAAALgAECgIJAwAAAA==.Timojj:BAAALgAECgEJAwAAAA==.Tinglu:BAAALgADCgcJCQAAAA==.Tinkk:BAAALgAECgcJEQAAAA==.Titø:BAAALgAECgYJCwAAAA==.',
To='Tomorrow:BAACLgAFFH8PAAILAAQJwxvRRgBNAQALAAQJwxvRRgBNAQAuAAQKfxoAAgsACAkpHvlOAEoCAAsACAkpHvlOAEoCAAAA.Topdog:BAAALgAECgUJBQAAAA==.Topzee:BAAALgAECgQJBwAAAA==.Torquin:BAAALgADCgMJAwAAAA==.Tottytotems:BAAALgADCgcJDAAAAA==.Touchmablade:BAAALgADCgQJBAAAAA==.',
Tr='Traylo:BAABLgAECn8oAAMIAAgJQhQwPwDaAQAIAAgJQhQwPwDaAQAYAAIJ/QCtigAxAAAAAA==.Treysong:BAAALgADCgMJAwAAAA==.',
Tu='Turkeymm:BAAALgADCgMJAwAAAA==.',
Tv='Tvak:BAABLgAECn8iAAIDAAkJICDRKQBQAgADAAkJICDRKQBQAgAAAA==.',
Tw='Twopump:BAABLgAECn8sAAIDAAkJBw56YAClAQADAAkJBw56YAClAQAAAA==.',
Ty='Tygrarelea:BAAALgAECgEJAQAAAA==.Tynan:BAAALgADCgUJDgAAAA==.Tyrah:BAAALgADCgQJBQAAAA==.',
Ul='Ulinova:BAABLgAECn8hAAIoAAgJZhO/BwC0AQAoAAgJZhO/BwC0AQAAAA==.',
Un='Unholly:BAAALgADCgcJBgAAAA==.',
Up='Uppercut:BAAALgAECgEJAQAAAA==.',
Ur='Uroro:BAAALgAFFAIJAwAAAA==.',
Uu='Uu:BAACLgAFFH8TAAMWAAMJvALkKwCJAAAWAAMJvALkKwCJAAAJAAMJYAFEQgCIAAAuAAQKfxYABAkABgnwCbBQALgAAAkABgl6CbBQALgAAA4AAglGAepoAC8AABYAAQkTA2qxABwAAAAA.',
Uz='Uzas:BAAALgAECgUJBgAAAA==.',
Va='Vaehi:BAAALgAECgEJAQAAAA==.Vaiden:BAAALgADCgEJAQAAAA==.Vainqueur:BAABLgAECn8YAAIfAAgJkBecBQD3AQAfAAgJkBecBQD3AQAAAA==.Valoroso:BAAALgAECgQJBAAAAA==.Vanarios:BAAALgAECgEJAgAAAA==.Vanderdemon:BAAALgAECgcJCQAAAA==.Vanderius:BAAALgAECgEJAQAAAA==.Vanderpal:BAAALgADCggJBgAAAA==.Vandersus:BAAALgAECgYJBQAAAA==.Vanec:BAAALgADCgMJAwAAAA==.Varm:BAAALgAECgEJAQAAAA==.Vasarian:BAAALgAECgEJAQAAAA==.Vayan:BAAALgADCgcJDQAAAA==.',
Ve='Veidima:BAAALgAECgQJBgAAAA==.Veigar:BAAALgADCgYJBgAAAA==.Velathrus:BAAALgADCgEJAQAAAA==.Velinamue:BAAALgAECgEJAQAAAA==.Velion:BAAALgAECgIJAwAAAA==.Velyine:BAAALgADCgQJBAAAAA==.Verzweifeln:BAAALgAECgYJDwAAAA==.Vesenya:BAAALgAECgIJAgAAAA==.Veyez:BAAALgADCgkJDAAAAA==.',
Vg='Vgx:BAAALgAECgIJAgAAAA==.',
Vh='Vhels:BAAALgADCgUJBQAAAA==.Vhyrix:BAAALgAECgQJBQAAAA==.',
Vi='Viantel:BAAALgAECgYJEAAAAA==.Vielitre:BAAALgADCgMJAwAAAA==.Viklicious:BAAALgADCgkJCQAAAA==.Vinarn:BAABLgAECn9FAAMUAAkJlBFZRQDqAQAUAAkJLBFZRQDqAQAjAAYJAg0ACgAzAQAAAA==.Vinyls:BAAALgAECgQJBQAAAA==.Viridias:BAAALgADCgIJAgAAAA==.Viridius:BAAALgAECgUJEAAAAA==.Virindi:BAAALgAECgEJAQAAAA==.Vishouspayne:BAAALgAECgMJCAAAAA==.',
Vo='Voidburn:BAAALgADCgUJBQAAAA==.',
Vr='Vrogar:BAABLgAFFH8HAAIXAAMJzgl4HwDIAAAXAAMJzgl4HwDIAAAAAA==.',
Vy='Vyntage:BAABLgAECn8iAAITAAkJ2RXeFgAhAgATAAkJ2RXeFgAhAgAAAA==.',
['Vä']='Väelün:BAABLgAECn8vAAIPAAcJPBZvTACUAQAPAAcJPBZvTACUAQABLgAECgkJJwAQABIRAA==.',
Wa='Wachoosh:BAAALgAECgYJEQAAAA==.Wackamoose:BAABLgAECn8hAAQCAAcJRB1LEgDIAQACAAcJRB1LEgDIAQAZAAQJ7g51MADAAAABAAIJmgdjlgBnAAAAAA==.Wagoogusmay:BAAALgAECgEJAQAAAA==.Waidmanns:BAACLgAFFH8JAAIIAAQJLQ/KWgDbAAAIAAQJLQ/KWgDbAAAuAAQKfy0AAwgACQk6HO0dAFICAAgACQk6HO0dAFICABcABQkuEwg0AAoBAAAA.Walkinredflg:BAAALgADCgYJBgAAAA==.Walvet:BAABLgAECn8aAAIcAAkJfRoYDgCAAgAcAAkJfRoYDgCAAgAAAA==.Warc:BAAALgADCgUJBQAAAA==.Wargramps:BAAALgADCgQJBAAAAA==.Warrioo:BAAALgADCgMJAwABLgAECgcJBwAGAAAAAA==.',
We='Weather:BAAALgAECgEJAQABLgAECggJFgALAJYIAA==.Weelad:BAAALgADCgkJFAAAAA==.Weldord:BAABLgAECn9DAAIIAAgJ2w2yYQB2AQAIAAgJ2w2yYQB2AQAAAA==.',
Wh='Whatorne:BAAALgAECgUJBgAAAA==.Whatyamean:BAAALgADCgQJBAAAAA==.Whiskeytaur:BAAALgADCgYJBgAAAA==.Whomonk:BAAALgAECgEJAQAAAA==.',
Wi='Wickedchick:BAABLgAECn8fAAIgAAYJcw5PQwDxAAAgAAYJcw5PQwDxAAAAAA==.Willock:BAAALgAECgUJCgAAAA==.Willowknight:BAAALgAECgMJAwAAAA==.Willöww:BAAALgAECgcJBwABLgAECggJHgAEAFITAA==.',
Wo='Wolvareene:BAAALgADCgcJBwAAAA==.',
Wr='Wrenn:BAAALgAFFAMJBAAAAA==.Wrongknight:BAAALgAECgQJDAAAAA==.Wrongname:BAAALgAECgUJEwAAAA==.',
Xa='Xalthérion:BAAALgAECgMJAwAAAA==.',
Xe='Xeruu:BAAALgADCgUJBQAAAA==.',
Xo='Xolan:BAACLgAFFH8FAAIEAAIJKQ20GwCOAAAEAAIJKQ20GwCOAAAuAAQKfx0AAgQACAkQGtYkACYCAAQACAkQGtYkACYCAAAA.',
Xp='Xprophet:BAABLgAECn8UAAIBAAYJvAQGZgC3AAABAAYJvAQGZgC3AAAAAA==.',
Xu='Xunghuai:BAAALgAECgEJAQAAAA==.',
Xw='Xw:BAAALgADCgYJCwAAAA==.',
['Xß']='Xß:BAAALgAECgcJCgAAAA==.',
Ye='Yemonyunter:BAAALgADCgUJBQAAAA==.Yesyesyes:BAAALgADCgIJAgAAAA==.',
Yo='Yogsothoth:BAECLgAFFH8JAAIIAAUJZQYjRwANAQAIAAUJZQYjRwANAQAuAAQKfyEAAwgACAmDFDpVAJcBAAgACAmIEzpVAJcBABcABgmMEGIWAGMBAAAA.Yooloakala:BAAALgADCggJCAAAAA==.Yormaum:BAAALgADCgYJBgAAAA==.Yosha:BAAALgADCgcJEAAAAA==.',
Za='Zaartyn:BAAALgAFFAEJAQAAAA==.Zalupalkys:BAAALgAECgQJAwAAAA==.Zarexion:BAAALgADCggJDAAAAA==.',
Ze='Zeebeth:BAABLgAECn8gAAIIAAkJ2hQkMwAFAgAIAAkJ2hQkMwAFAgAAAA==.Zefi:BAABLgAECn8cAAIiAAkJkg/OGgB7AQAiAAkJkg/OGgB7AQAAAA==.Zenko:BAAALgADCgQJBAAAAA==.Zerokai:BAAALgAFFAMJAwAAAA==.',
Zh='Zhahira:BAAALgAECgUJDQAAAA==.',
Zi='Zipsy:BAACLgAFFH8JAAILAAMJeQYphADHAAALAAMJeQYphADHAAAuAAQKfzAAAgsACQlUDzFXANEBAAsACQlUDzFXANEBAAAA.',
Zo='Zomlo:BAAALgAECgEJAQAAAA==.Zonka:BAAALgAECgEJAQABLgAFFAEJAQAGAAAAAA==.',
Zu='Zumtobel:BAAALgAECgQJBwAAAA==.Zuuko:BAACLgAFFH8fAAIWAAUJZCUZBQC4AQAWAAUJZCUZBQC4AQAuAAQKfykAAhYACQkqJjIEAA8DABYACQkqJjIEAA8DAAAA.',
Zy='Zyreth:BAAALgAECgcJDQAAAA==.',
['Ár']='Árthur:BAAALgAECgUJBwAAAA==.',
['Âr']='Ârtemis:BAAALgAECgUJBQABLgAFFAUJCwAJAKMJAA==.',
['År']='Åres:BAAALgAECgMJBgAAAA==.',
['Îs']='Îsadora:BAAALgADCgYJCQAAAA==.',
['Ýe']='Ýe:BAAALgADCgYJBgAAAA==.',
['ßu']='ßuzzibee:BAAALgAECgUJEQABLgAFFAMJCQASAIEQAA==.',
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
