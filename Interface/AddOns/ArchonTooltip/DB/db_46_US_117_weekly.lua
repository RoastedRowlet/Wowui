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

local lookup = {'Warrior-Fury','Warrior-Arms','Paladin-Retribution','Druid-Restoration','Warlock-Demonology','Unknown-Unknown','Paladin-Protection','Hunter-BeastMastery','Monk-Brewmaster','Paladin-Holy','Mage-Frost','Warlock-Affliction','Warlock-Destruction','Monk-Mistweaver','DemonHunter-Devourer','Druid-Guardian','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Elemental','DeathKnight-Unholy','Rogue-Subtlety','Monk-Windwalker','Hunter-Survival','Hunter-Marksmanship','Warrior-Protection','Evoker-Augmentation','Priest-Shadow','Mage-Arcane','Priest-Discipline','Evoker-Preservation','Evoker-Devastation','Druid-Balance','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Frost','Priest-Holy','Druid-Feral','Rogue-Assassination','Mage-Fire','Rogue-Outlaw',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=46,date='2026-05-30',data={Ac='Acheros:BAAALgADCgEJAQAAAA==.Actionfigure:BAABLgAECn8nAAMBAAkJFSIwCwCfAgABAAkJFSIwCwCfAgACAAEJ7AY0RwAoAAAAAA==.',
Ad='Adessa:BAAALgAECgQJBgAAAA==.Adgavery:BAABLgAECn8aAAIDAAgJAQ+rewBcAQADAAgJAQ+rewBcAQAAAA==.Adielia:BAABLgAECn8fAAIEAAgJ+hueGwBVAgAEAAgJ+hueGwBVAgAAAA==.',
Ae='Aeleara:BAAALgAECgUJBQABLgAECgkJLwAFAGsZAA==.Aellip:BAAALgADCgEJAQAAAA==.Aeskir:BAAALgAECgcJAQAAAA==.Aevalaana:BAAALgADCggJCAAAAA==.',
Af='Afton:BAAALgADCgMJAwAAAA==.',
Ah='Ahnho:BAAALgADCgQJBAAAAA==.',
Ak='Akaim:BAAALgADCgIJAwAAAA==.Aksa:BAAALgAFFAEJAQAAAA==.',
Al='Alantharia:BAAALgADCgMJAwABLgAECgUJCQAGAAAAAA==.Alexious:BAACLgAFFH8WAAIHAAUJPyG8AgBxAQAHAAUJPyG8AgBxAQAuAAQKfyQAAgcACAlWIkIDAOwCAAcACAlWIkIDAOwCAAAA.Alkapwnn:BAAALgAECgUJDAAAAA==.Aloefox:BAAALgADCgkJKQAAAA==.Alofyxe:BAABLgAECn8nAAIIAAkJMCCCCwDlAgAIAAkJMCCCCwDlAgAAAA==.Altagravee:BAAALgADCgQJBAAAAA==.Altdiezzel:BAAALgAECgkJCQAAAA==.Altffour:BAABLgAFFH8NAAIJAAMJvQO2GACnAAAJAAMJvQO2GACnAAAAAA==.Alulla:BAACLgAFFH8XAAIBAAYJExgUCwCLAQABAAYJExgUCwCLAQAuAAQKfyIAAgEACAndIkISAE8CAAEACAndIkISAE8CAAAA.Alunira:BAABLgAECn83AAMKAAkJmRxpEwB3AgAKAAkJmRxpEwB3AgADAAcJiRYKbwB2AQAAAA==.',
Am='Amberrfrost:BAABLgAECn8dAAILAAcJqAWOxADkAAALAAcJqAWOxADkAAAAAA==.Amberveil:BAAALgADCgYJBgAAAA==.Amex:BAAALgAECgEJAQAAAA==.',
An='Andark:BAAALgAECgMJAwAAAA==.Angryhtr:BAAALgAECgYJCQAAAA==.Angrylina:BAAALgAECgEJAQAAAA==.Anumo:BAAALgAECgEJAQAAAA==.',
Ap='Aphox:BAABLgAECn8vAAQFAAkJaxklLwAPAgAFAAkJJBUlLwAPAgAMAAcJ1xeZCwCBAQANAAMJLBPKKQBfAAAAAA==.Apokalypto:BAAALgAECgYJCQAAAA==.',
Ar='Arachnida:BAAALgADCgcJDAAAAA==.Arairi:BAAALgAECgQJBAABLgAECgYJEQAGAAAAAA==.Aravera:BAAALgAECgMJAwAAAA==.Araxes:BAAALgAECgMJBwAAAA==.Arcanefox:BAABLgAECn8YAAILAAcJmws5nwAiAQALAAcJmws5nwAiAQAAAA==.Arcenius:BAAALgAECgUJBgAAAA==.Arcåedeå:BAAALgAECgEJAQAAAA==.Ardelan:BAAALgADCggJCgAAAA==.Arîse:BAAALgADCgUJCAAAAA==.',
As='Ashgold:BAAALgAECgEJAQAAAA==.Ashoggal:BAAALgADCgQJBgAAAA==.Ashyl:BAAALgAECgEJAQAAAA==.Aslunay:BAABLgAECn8jAAIDAAYJRwwDwADqAAADAAYJRwwDwADqAAAAAA==.Assine:BAAALgADCgIJAgABLgAECgcJBwAGAAAAAA==.Astanis:BAABLgAECn8UAAIOAAgJyAeyTAAEAQAOAAgJyAeyTAAEAQAAAA==.Asteriia:BAABLgAECn8vAAIPAAgJZQ80XABbAQAPAAgJZQ80XABbAQAAAA==.',
At='Athhena:BAAALgADCgQJBgAAAA==.Atomskdmn:BAAALgADCgEJAQAAAA==.',
Au='Augustino:BAAALgAECgIJAgAAAA==.',
Av='Avraelia:BAAALgAECgYJCwAAAA==.',
Aw='Awakemoon:BAABLgAECn8aAAIQAAgJnyR+AwDZAgAQAAgJnyR+AwDZAgAAAA==.',
Az='Azarazan:BAAALgADCgIJAgAAAA==.Azaria:BAAALgADCgkJDQABLgAECgEJAQAGAAAAAA==.Azenderv:BAABLgAECn8gAAILAAcJ5wShyADdAAALAAcJ5wShyADdAAAAAA==.Azka:BAABLgAECn8rAAIDAAgJWyMqGACcAgADAAgJWyMqGACcAgAAAA==.Azkadk:BAAALgAECggJEwAAAA==.Azkamage:BAAALgAECgYJCQAAAA==.Azshaloria:BAAALgAECgYJDgAAAA==.Azter:BAAALgADCgMJAwAAAA==.Azzline:BAAALgADCgcJBwAAAA==.',
Ba='Babybilly:BAABLgAECn8UAAIDAAgJ/gyQiQBCAQADAAgJ/gyQiQBCAQAAAA==.Baddieelf:BAAALgAECgYJEAAAAA==.Bakkasura:BAAALgAFFAEJAQABLgAFFAEJAQAGAAAAAA==.Balduran:BAAALgADCgMJAwAAAA==.Baludis:BAAALgAECgYJCgAAAA==.Bamff:BAABLgAECn8ZAAILAAgJSBmSWgC1AQALAAgJSBmSWgC1AQAAAA==.Bast:BAACLgAFFH8HAAIRAAMJNBQMBwDDAAARAAMJNBQMBwDDAAAuAAQKfyUAAxEACAlqIYoCAMwCABEACAlqIYoCAMwCABIAAgk7CaNmACsAAAEuAAUUBQkLAAkAowkA.Bastbrew:BAABLgAFFH8LAAIJAAUJowmYKQDwAAAJAAUJowmYKQDwAAAAAA==.Basthara:BAAALgAFFAQJBAABLgAFFAUJCwAJAKMJAA==.Batracio:BAABLgAECn8uAAMPAAkJshVEMADvAQAPAAkJohREMADvAQASAAYJsRXAJQAmAQAAAA==.Batrancho:BAAALgADCgQJBAAAAA==.Batshiz:BAAALgADCgUJBQAAAA==.',
Be='Bearlylivin:BAAALgAECgEJAgABLgAECgcJCwAGAAAAAA==.Beerox:BAAALgADCgIJAgAAAA==.Belindah:BAAALgADCgcJDAABLgAECggJHgAEAFITAA==.Bellemore:BAAALgAECgYJBgAAAA==.Benif:BAACLgAFFH8VAAMBAAYJCR99DgBvAQABAAUJ9SJ9DgBvAQACAAEJWA8FMQBQAAAuAAQKfz0AAwEACQk7JW4DACQDAAEACQk7JW4DACQDAAIABAn1GqwnABkBAAAA.Bertodruid:BAAALgADCgYJBgAAAA==.Bertorod:BAABLgAECn8hAAITAAkJkx84CgCnAgATAAkJkx84CgCnAgAAAA==.',
Bh='Bhaall:BAABLgAECn8WAAIUAAYJ4AeLwQAAAQAUAAYJ4AeLwQAAAQAAAA==.',
Bi='Bigbitehotdo:BAABLgAFFH8JAAIOAAMJvRJULQC8AAAOAAMJvRJULQC8AAABLgAFFAMJEwAUAPImAA==.Bigboppa:BAAALgADCgEJAQAAAA==.Bigknife:BAABLgAECn8aAAIVAAYJmRUsJQBQAQAVAAYJmRUsJQBQAQAAAA==.Bigstunna:BAAALgADCgMJBAAAAA==.Bigtommybuns:BAAALgAECgMJBAAAAA==.Binkyfiasco:BAABLgAECn8vAAMJAAkJsiMUBAD7AgAJAAkJsiMUBAD7AgAWAAEJphiPeQA3AAAAAA==.',
Bl='Blaqlight:BAAALgADCgEJAQAAAA==.Bloblop:BAAALgAECgkJBgAAAA==.Blockybird:BAAALgAECgIJAgAAAA==.Bloodstoned:BAAALgAECgEJAQAAAA==.Bloodtank:BAAALgAECgYJEgAAAA==.',
Bm='Bmanblastmas:BAAALgAECgEJAQAAAA==.',
Bo='Bobquat:BAAALgADCgIJAwAAAA==.Bolcy:BAACLgAFFH8OAAQXAAQJTxLJEAA4AQAXAAQJahHJEAA4AQAIAAQJ0Aw3PwAPAQAYAAEJyAFeLQA9AAAuAAQKfxkABAgACAnSG1FFALoBAAgABwmWH1FFALoBABgABAm1Eg9RAAkBABcAAQkrEPRTAEMAAAAA.Bonaparte:BAAALgADCgYJBgAAAA==.Bonerott:BAAALgAECgcJCAAAAA==.Boogat:BAABLgAECn8dAAIZAAcJ8wMBLgC0AAAZAAcJ8wMBLgC0AAAAAA==.Boonkgang:BAAALgADCgEJAQAAAA==.Bowjangles:BAAALgADCgUJBQAAAA==.',
Br='Brahd:BAAALgAECggJCAAAAA==.Brauck:BAACLgAFFH8VAAIFAAUJdCKvHwCVAQAFAAUJdCKvHwCVAQAuAAQKfyUAAw0ACAmvIEUYAIgBAAUABQnSIdFSAM8BAA0ABQk3H0UYAIgBAAEuAAUUBwkWABoAaRkA.Brewbrewbrew:BAAALgAECgMJAwAAAA==.Brittarcher:BAAALgAECgcJDAAAAA==.Brixlo:BAAALgAECgYJCgABLgAECgkJKgAbAIkJAA==.',
Bu='Bubblegum:BAAALgADCgMJAQAAAA==.Buffmuffin:BAAALgAECgEJAgAAAA==.Bugslyfe:BAAALgADCggJCAAAAA==.Bullcat:BAAALgADCgEJAQAAAA==.Bunbohue:BAABLgAECn8XAAIPAAcJtROSWQCVAQAPAAcJtROSWQCVAQAAAA==.Burblbiblr:BAAALgAECgMJAwAAAA==.Burni:BAAALgAECgQJBAAAAA==.Burningbubba:BAAALgAECgcJBQAAAA==.Burp:BAACLgAFFH8cAAQFAAgJ+Bi8HACiAQAFAAYJwxe8HACiAQANAAMJqRbGDQCsAAAMAAIJUyTXEQBhAAAuAAQKfysABA0ACAl6JeQUAKMBAAUABgm2JZ80ADkCAA0ABAmCJOQUAKMBAAwAAwnqJI4OAEgBAAAA.Burped:BAAALgAECgQJCAAAAA==.',
['Bü']='Büllseye:BAAALgAECgEJAQAAAA==.',
Ca='Caadonnu:BAAALgAECgYJCAAAAA==.Cambrier:BAACLgAFFH8NAAIBAAMJjh7rIwAJAQABAAMJjh7rIwAJAQAuAAQKf0MAAgEACQlEI4cEAAsDAAEACQlEI4cEAAsDAAAA.Canol:BAAALgADCgEJAQAAAA==.Cardinal:BAAALgAECgcJDwAAAA==.Carynden:BAAALgAECgYJBgAAAA==.Castbo:BAABLgAFFH8HAAILAAMJlB8zXgAVAQALAAMJlB8zXgAVAQAAAA==.Caylie:BAAALgADCgEJAwAAAA==.Cazbirkzul:BAAALgADCgEJAQAAAA==.',
Ce='Celeniel:BAABLgAFFH8IAAMcAAQJbgbWAQDNAAAcAAQJ6wLWAQDNAAALAAIJoQhYlACMAAAAAA==.Celorne:BAAALgADCgEJAQAAAA==.Cerestra:BAAALgADCgEJAQAAAA==.Cerostus:BAAALgAECgUJBQAAAA==.',
Ch='Chaladaug:BAAALgAECgIJAQAAAA==.Chaladk:BAAALgAECgcJBwAAAA==.Charcharwar:BAABLgAECn9CAAICAAcJ2Bg3FgCSAQACAAcJ2Bg3FgCSAQAAAA==.Charknight:BAAALgAECgMJDAAAAA==.Charmaldin:BAAALgADCgMJAwAAAA==.Chatdodu:BAAALgAECgYJEQAAAA==.Chatnoir:BAAALgAECgcJDgAAAA==.Chulu:BAAALgADCgcJCwAAAA==.Chunklleria:BAAALgAECgMJBAABLgAECgkJNAABANUiAA==.Chunks:BAABLgAECn80AAQBAAkJ1SImBwDdAgABAAkJ1SImBwDdAgAZAAcJ3RiiEQDtAQACAAcJyBHKHABdAQAAAA==.Chunkvourer:BAAALgADCgUJAwABLgAECgkJNAABANUiAA==.',
Ci='Cinci:BAAALgADCgkJCgAAAA==.Cinderazer:BAAALgAECgMJAQAAAA==.Cipherdam:BAAALgAECgIJAgAAAA==.',
Co='Colesiaw:BAAALgAECgEJAQAAAA==.Colress:BAAALgAFFAEJAQAAAA==.Conduit:BAAALgAECgYJDAAAAA==.Cormier:BAAALgAECgQJCgABLgAECgcJDAAGAAAAAA==.Covidvax:BAAALgADCgEJAQAAAA==.',
Cr='Cronnie:BAAALgAECgMJBwAAAA==.Cryodormu:BAAALgAECgYJCgAAAA==.',
Ct='Ctrlaltd:BAAALgAECgEJAQAAAA==.',
Cu='Cubo:BAAALgADCgEJAQAAAA==.',
Cw='Cwarr:BAACLgAFFH8MAAMDAAMJzhcnVwDfAAADAAMJwREnVwDfAAAHAAIJVhU9DgB5AAAuAAQKfx4AAwcABwlPH5gJABsCAAcABwlPH5gJABsCAAMABwmoDiOaACUBAAEuAAUUBQkaABoAdRQA.',
Cy='Cyrcee:BAAALgADCggJCAABLgAECggJHgAEAFITAA==.',
Da='Dabast:BAAALgAECgMJBAABLgAFFAUJCwAJAKMJAA==.Daddyluis:BAAALgAECgQJBwAAAA==.Daddywarbuck:BAAALgAECgEJAQAAAA==.Danat:BAAALgAECgEJAQAAAA==.Dandanh:BAAALgADCggJDgAAAA==.Dandathun:BAAALgAECgEJAQAAAA==.Dankbo:BAACLgAFFH8HAAIdAAIJLiWQJwDWAAAdAAIJLiWQJwDWAAAuAAQKf0MAAh0ACQmAJkgAAPADAB0ACQmAJkgAAPADAAAA.Dankbro:BAAALgADCgUJBQAAAA==.Darkcoffee:BAABLgAFFH8IAAMHAAMJTxlRCwCnAAAHAAIJdRxRCwCnAAADAAEJAxPnkQBPAAAAAA==.Darkivie:BAABLgAECn8VAAIIAAgJlQIYpQDZAAAIAAgJlQIYpQDZAAABLgAFFAMJDAAaAIUAAA==.Darkjoker:BAAALgAECgMJAwAAAA==.Darthmama:BAAALgADCgIJAgAAAA==.',
Dc='Dcbuster:BAABLgAECn8nAAIBAAgJbRdDMQDoAQABAAgJbRdDMQDoAQAAAA==.',
De='Deathshrimp:BAAALgADCgcJCwAAAA==.Delaylea:BAAALgAECgUJBgAAAA==.Demonhusk:BAAALgAECgYJDAAAAA==.Demoni:BAAALgADCgcJBwAAAA==.Demonicsword:BAAALgAECgYJCwAAAA==.Demonz:BAAALgADCgcJCgAAAA==.Denaheal:BAAALgADCgkJDgABLgAECgcJFgAIAMQVAA==.Denissa:BAAALgAECgQJBAAAAA==.Devildj:BAAALgAECgcJDAAAAA==.',
Dh='Dhampyra:BAABLgAECn8gAAIbAAkJkB6iDABuAgAbAAkJkB6iDABuAgAAAA==.',
Di='Dianasia:BAAALgAECgQJBAAAAA==.Dietdrkelps:BAAALgAECgQJBAABLgAECgcJGwABAA8bAA==.Dietmountdew:BAAALgAECgUJCQAAAA==.Dimitrios:BAAALgAECgQJBwAAAA==.Dingadinga:BAAALgAECgYJEQAAAA==.Dirtlicker:BAAALgADCgIJAgAAAA==.Disconnect:BAAALgAECgYJEwAAAA==.Divindragosa:BAAALgADCgEJAQAAAA==.Dixxonciderr:BAACLgAFFH8VAAIeAAQJmBugEQBXAQAeAAQJmBugEQBXAQAuAAQKf0gABB4ACQkgINEBAGIDAB4ACQkgINEBAGIDAB8ABgnhFZULAEkBABoABQmaBcpwAF4AAAAA.',
Dk='Dkjaypim:BAAALgAECgIJAgAAAA==.',
Dm='Dmoe:BAABLgAECn8WAAILAAYJcxPXmAAtAQALAAYJcxPXmAAtAQAAAA==.',
Do='Dorkdark:BAAALgAECgMJAwAAAA==.',
Dr='Dragonflyer:BAAALgAFFAEJAQABLgAFFAEJAQAGAAAAAA==.Drioksis:BAABLgAECn8XAAITAAYJjg6PTADmAAATAAYJjg6PTADmAAAAAA==.Drshaboinkyy:BAACLgAFFH8LAAIPAAUJzxJmCQCUAQAPAAUJzxJmCQCUAQAuAAQKfxQAAw8ACAmYIgIuAEUCAA8ACAmYIgIuAEUCABEABwlEA8UqADYAAAAA.Drshbuinky:BAAALgAECgYJBwAAAA==.Druyalulz:BAAALgAECgcJDwAAAA==.',
Du='Duckboy:BAAALgADCgUJBwAAAA==.Duluekin:BAAALgAECgMJBQAAAA==.Dumag:BAABLgAECn8lAAIJAAgJOyIACgCCAgAJAAgJOyIACgCCAgAAAA==.Duplicate:BAACLgAFFH8bAAILAAQJ2g+IUQAuAQALAAQJ2g+IUQAuAQAuAAQKf0oAAgsACQlUIXgOAPICAAsACQlUIXgOAPICAAAA.Durto:BAAALgAECgIJAgABLgAECgQJCAAGAAAAAA==.Dustdruid:BAABLgAFFH8UAAIgAAUJzhZ4FwAwAQAgAAUJzhZ4FwAwAQAAAA==.Dustlock:BAAALgAECgQJBAAAAA==.',
Dw='Dwighthowelf:BAAALgAECgEJAgAAAA==.',
Dy='Dyorah:BAAALgADCgYJBgAAAA==.',
Eb='Ebonsnoot:BAAALgADCgEJAQAAAA==.',
Ee='Eender:BAAALgADCgcJDgAAAA==.',
Eg='Eggrolls:BAAALgAECgQJEAAAAA==.',
El='Elfrafa:BAAALgADCgUJAwAAAA==.Elif:BAAALgADCgEJAQAAAA==.Eliotyy:BAAALgADCgYJCgAAAA==.Ellcrys:BAABLgAECn8wAAIEAAkJ+RIvLQDgAQAEAAkJ+RIvLQDgAQAAAA==.Elletta:BAAALgAECgIJCQAAAA==.Ellssa:BAABLgAECn8dAAILAAYJvARS6QCqAAALAAYJvARS6QCqAAAAAA==.Elmamonster:BAAALgAECgQJBwAAAA==.',
Em='Emerick:BAAALgADCgYJBQAAAA==.Emillie:BAAALgAECgYJEQAAAA==.',
Eo='Eobeob:BAAALgAECggJDwAAAA==.',
Ep='Epora:BAAALgADCgEJAQABLgAECgEJAQAGAAAAAA==.',
Er='Ersande:BAAALgADCggJCwAAAA==.',
Es='Estellia:BAAALgADCgUJBQAAAA==.Estheban:BAABLgAECn8/AAQeAAgJqiX0AQBaAwAeAAgJqiX0AQBaAwAfAAUJwhdZCgBmAQAaAAMJ4QhYhQAwAAAAAA==.',
Ex='Exodia:BAAALgAECgYJCQAAAA==.',
Fa='Face:BAABLgAECn8mAAIPAAgJBhX3PAC8AQAPAAgJBhX3PAC8AQAAAA==.Faelila:BAAALgADCgYJBgAAAA==.Fairgrim:BAAALgAECgUJCAAAAA==.Falin:BAACLgAFFH8HAAIDAAMJBQStbgCjAAADAAMJBQStbgCjAAAuAAQKf2wAAgMACQmvHmIbAIgCAAMACQmvHmIbAIgCAAAA.Falthras:BAAALgAECgYJDAAAAA==.Fanethben:BAAALgAECgYJCwAAAA==.Faqueuedark:BAACLgAFFH8IAAMFAAMJUA97cQDHAAAFAAMJUA97cQDHAAAMAAEJVBe+HABOAAAuAAQKfx8ABAUACAmPIFcrAGICAAUACAkDIFcrAGICAAwAAgkXIQMYALsAAA0AAQkAAEZuADkAAAAA.Faqueueeight:BAAALgAFFAEJAQABLgAFFAMJCAAFAFAPAA==.Faqueuetoo:BAAALgAECgUJBAABLgAFFAMJCAAFAFAPAA==.Fatsloth:BAAALgAECgIJBAAAAA==.Fatébringer:BAAALgAECgMJAwABLgAECgcJDgAGAAAAAA==.Fazt:BAAALgADCgUJCAAAAA==.',
Fe='Feironos:BAABLgAECn8UAAIfAAMJygTIGgBlAAAfAAMJygTIGgBlAAAAAA==.Felray:BAAALgADCgUJCAAAAA==.Ferairi:BAAALgAECgQJCgABLgAECgYJEQAGAAAAAA==.Fereir:BAAALgADCgQJBAAAAA==.Ferndavia:BAABLgAECn8WAAIIAAcJxBUDYwBnAQAIAAcJxBUDYwBnAQAAAA==.',
Fi='Fiist:BAAALgADCgYJDgAAAA==.Filigree:BAAALgADCgYJBgAAAA==.Fimtastic:BAABLgAECn8lAAMhAAkJlg20QACOAQAhAAkJlg20QACOAQATAAYJ2wONZACbAAAAAA==.Finasy:BAABLgAECn87AAQiAAkJTyO2AgASAwAiAAkJTyO2AgASAwAUAAQJxhIFzADWAAAjAAEJ4g9IFwAzAAAAAA==.Finnicka:BAAALgAECgYJBgAAAA==.Firefaux:BAAALgAECgEJAQAAAA==.Fireouch:BAAALgAECgEJAQAAAA==.Firevag:BAAALgAECgMJAwAAAA==.Fistymisty:BAAALgAECggJDAAAAA==.',
Fl='Flaynpray:BAAALgAECgcJAgAAAA==.Flopsie:BAAALgAECgkJDwAAAA==.',
Fo='Fonzsupreme:BAABLgAECn8YAAILAAYJniKkVwAyAgALAAYJniKkVwAyAgABLgAFFAUJFQAZAK0hAA==.Foxkit:BAAALgAECgEJAgAAAA==.Foxrawruwu:BAAALgAFFAEJAQAAAA==.',
Fr='Fredox:BAAALgADCgcJBwAAAA==.Freemilk:BAAALgAECgIJAwAAAA==.Frostbight:BAAALgADCgUJCwAAAA==.Frostyflake:BAAALgADCgUJBQAAAA==.',
Fu='Furearia:BAAALgAECgMJAwAAAA==.Furrybowner:BAABLgAECn8YAAIIAAYJnRVpcwBAAQAIAAYJnRVpcwBAAQAAAA==.',
['Fó']='Fóx:BAAALgAFFAEJAQAAAA==.',
Ga='Gabrielfury:BAAALgAECgkJCQAAAA==.Gaelai:BAAALgAECgUJDAAAAA==.Galeriel:BAACLgAFFH8VAAIkAAQJoRjSDQBJAQAkAAQJoRjSDQBJAQAuAAQKf0EAAiQACQkfHyQGAAIDACQACQkfHyQGAAIDAAAA.Gallethline:BAABLgAECn8WAAISAAYJPQIcSwBiAAASAAYJPQIcSwBiAAAAAA==.Garault:BAAALgAFFAIJBAAAAA==.',
Ge='Gekoni:BAABLgAECn8aAAIHAAkJnwpkJQDdAAAHAAkJnwpkJQDdAAAAAA==.Genna:BAAALgADCgEJAQAAAA==.Geodin:BAAALgAECgYJCwAAAA==.Geonon:BAABLgAECn8qAAILAAgJ3Q6ZcAB/AQALAAgJ3Q6ZcAB/AQAAAA==.Georgemoyd:BAAALgADCgkJCwAAAA==.',
Gh='Ghormehsubzi:BAAALgAECgEJAQAAAA==.',
Gi='Girthybeam:BAAALgAECgUJDAAAAA==.',
Gl='Glandrien:BAAALgAECgMJAwAAAA==.Glazar:BAAALgADCgkJDQAAAA==.Gloomshak:BAAALgAECgMJAgAAAA==.Glowclaws:BAAALgADCgQJAwAAAA==.Glowpwr:BAAALgADCgMJAwAAAA==.',
Go='Gobblerella:BAAALgADCgMJAwAAAA==.Gobeullin:BAAALgAFFAEJAQAAAA==.Goonthergg:BAAALgADCgkJEAAAAA==.Gothmog:BAAALgADCgMJAwAAAA==.',
Gr='Graytonson:BAAALgAECgEJAQAAAA==.Greenhills:BAAALgADCgIJAgAAAA==.Greenlocks:BAAALgADCgIJAgABLgAFFAEJAQAGAAAAAA==.Greenrånger:BAAALgAECgQJCwAAAA==.Greybush:BAABLgAECn8UAAILAAYJqRDDpwATAQALAAYJqRDDpwATAQAAAA==.Griffithw:BAAALgADCgYJCwAAAA==.Grija:BAAALgAFFAQJAQAAAA==.Grizzlettz:BAAALgAECgEJAQAAAA==.Grombrindil:BAAALgAECgIJAgABLgAECggJHQAWANQMAA==.Grullander:BAABLgAECn8wAAIhAAkJ2Bm3FQCDAgAhAAkJ2Bm3FQCDAgABLgAFFAEJAQAGAAAAAA==.Grullandur:BAAALgAECgQJBAABLgAFFAEJAQAGAAAAAA==.',
Gu='Guideau:BAAALgAECgEJAQAAAA==.Guiguiie:BAAALgADCgcJBwAAAA==.Gusthemighty:BAAALgADCgEJAQAAAA==.',
['Gó']='Gólden:BAAALgADCgYJBgAAAA==.',
Ha='Hahacx:BAACLgAFFH8CAAIPAAIJjxeEgQBKAAAPAAIJjxeEgQBKAAAuAAQKfxkAAg8ACAmdIVsSAOwCAA8ACAmdIVsSAOwCAAAA.Halama:BAAALgADCgcJDAAAAA==.Halazzì:BAAALgAECgMJAwAAAA==.Haleon:BAAALgAECgIJAgAAAA==.Haraharotou:BAAALgAECgMJBgAAAA==.Hardyhar:BAAALgADCgMJBAAAAA==.',
He='Hebrews:BAAALgADCgYJBgAAAA==.Helane:BAAALgAECgcJCwAAAA==.Herkharu:BAABLgAECn8oAAITAAkJ9BQ1GwDvAQATAAkJ9BQ1GwDvAQAAAA==.Hermionee:BAAALgAECgUJDAAAAA==.',
Hi='Himjongun:BAABLgAECn8bAAMSAAYJ1g+yLABkAQASAAYJPQ+yLABkAQAPAAYJqwlOnQDIAAAAAA==.',
Ho='Hobbitdemon:BAAALgAECgQJBAAAAA==.Hobbitdruid:BAABLgAECn8dAAMEAAcJ5AUidADHAAAEAAcJ5AUidADHAAAQAAYJQAtcNACvAAAAAA==.Hobbitlight:BAAALgAECgUJBgAAAA==.Hobbitpriest:BAAALgADCgUJBQAAAA==.Hobbitvoid:BAAALgAECgEJAQAAAA==.Holydagoon:BAAALgADCgYJBgABLgAFFAcJFgAaAGkZAA==.Hoother:BAACLgAFFH8PAAIEAAUJrRmQFQCRAQAEAAUJrRmQFQCRAQAuAAQKfxQAAgQACAmdG3kVAIoCAAQACAmdG3kVAIoCAAAA.Hoppingmuff:BAAALgADCgcJDQAAAA==.',
Hu='Humble:BAAALgADCgEJAQAAAA==.Hunia:BAABLgAECn8UAAIIAAcJ/wkmhwAXAQAIAAcJ/wkmhwAXAQAAAA==.Huntagrizz:BAAALgADCgIJAgAAAA==.Huntieluis:BAAALgAECgQJBAAAAA==.Hurndredd:BAAALgAECgIJAwAAAA==.Huuh:BAAALgADCgMJBgAAAA==.',
Hy='Hystericc:BAAALgAECgYJCQAAAA==.',
['Hé']='Héboric:BAABLgAECn8YAAIKAAgJZBc7HAALAgAKAAgJZBc7HAALAgAAAA==.',
['Hõ']='Hõlycow:BAAALgAECgcJDQAAAA==.',
Id='Idolon:BAAALgADCggJHQAAAA==.',
Ik='Ikala:BAAALgAECgQJBAAAAA==.Ikashi:BAAALgADCgEJAQAAAA==.Ikodiwa:BAAALgAECgYJEQAAAA==.',
Il='Ilisa:BAAALgADCgMJAwAAAA==.Ilrion:BAABLgAECn8cAAMgAAkJtgtjNgAhAQAgAAcJbAxjNgAhAQAEAAYJCQeFiQDCAAAAAA==.',
In='Indravax:BAAALgAECgMJBQAAAA==.Inferno:BAAALgAECgEJAwAAAA==.',
Is='Iseehot:BAABLgAECn8hAAILAAYJah7OfABkAQALAAYJah7OfABkAQAAAA==.',
Iv='Ivantis:BAAALgAECgYJEwAAAA==.Ivie:BAABLgAECn8eAAMEAAgJUhNKOgCZAQAEAAgJUhNKOgCZAQAgAAIJwA36aQBcAAAAAA==.Ivieenfuego:BAACLgAFFH8MAAIaAAMJhQBbTwBnAAAaAAMJhQBbTwBnAAAuAAQKfzUAAhoACQliBUxHAOoAABoACQliBUxHAOoAAAAA.',
Ja='Jackjack:BAAALgAFFAEJAQABLgAFFAMJBAAGAAAAAA==.Jackjackk:BAAALgAFFAMJBAAAAA==.Jadednurse:BAABLgAECn8VAAMkAAYJVhasMAAzAQAkAAYJVhasMAAzAQAdAAQJVAfWTwCRAAAAAA==.Jakisormjr:BAAALgADCgIJAgAAAA==.Jalanii:BAABLgAECn8kAAIDAAkJeRAVSwDNAQADAAkJeRAVSwDNAQAAAA==.Janjor:BAACLgAFFH8PAAITAAQJNxN0HAAVAQATAAQJNxN0HAAVAQAuAAQKfzQAAxMACQkuHgIPAGoCABMACQkuHgIPAGoCACEABAn3G3GjAF8AAAAA.Janjorski:BAAALgADCgQJBAAAAA==.Jayrior:BAAALgADCgcJCwAAAA==.',
Je='Jehlock:BAAALgAECgUJCgAAAA==.Jehvoker:BAAALgAECggJEgABLgAECgUJCgAGAAAAAA==.Jerghal:BAAALgAECgYJEAAAAA==.Jesthos:BAAALgAECgcJAgABLgAECgcJCwAGAAAAAA==.Jettian:BAABLgAECn8fAAIUAAYJXBICkgAuAQAUAAYJXBICkgAuAQAAAA==.',
Ji='Jinu:BAAALgADCgIJAgAAAA==.',
Jj='Jjdruid:BAAALgAECgEJAQAAAA==.',
Jo='Jockwork:BAAALgAECgQJDQAAAA==.Jokeer:BAAALgAECgUJDgAAAA==.Jolene:BAABLgAECn8aAAIgAAcJbgrERQDYAAAgAAcJbgrERQDYAAAAAA==.Jollygreene:BAABLgAECn8dAAIgAAYJTAanUACvAAAgAAYJTAanUACvAAAAAA==.Joyina:BAAALgADCgkJIgAAAA==.',
Ju='Juggærnaut:BAAALgAECgIJAwAAAA==.Junjie:BAAALgAECgMJAwAAAA==.Justicee:BAAALgAECgQJCAABLgAECggJDAAGAAAAAA==.',
Jx='Jxy:BAAALgAECgUJCQABLgAFFAgJJAAPADMdAA==.',
Ka='Kachess:BAAALgADCgkJCQAAAA==.Kaddar:BAAALgADCgYJBgAAAA==.Kahri:BAABLgAECn8hAAQQAAgJDBtDCgAiAgAQAAgJDBtDCgAiAgAlAAUJxBN8HwDlAAAEAAEJiAWI3gAhAAAAAA==.Kakali:BAAALgAECgcJCAAAAA==.Kalend:BAAALgAECgMJAwAAAA==.Karametra:BAAALgAECgEJAQAAAA==.Karlager:BAABLgAECn8dAAIWAAgJ1AycKwBIAQAWAAgJ1AycKwBIAQAAAA==.Karlain:BAAALgAECgYJDQAAAA==.Karldun:BAAALgADCggJCAABLgAECggJHQAWANQMAA==.Kasaide:BAAALgADCgcJDQABLgAECgkJKwAFAJkPAA==.Kasmir:BAABLgAECn8rAAIFAAkJmQ9ZSAC2AQAFAAkJmQ9ZSAC2AQAAAA==.Katia:BAAALgADCgUJBwAAAA==.Kaylana:BAAALgADCgEJAQAAAA==.Kazoo:BAAALgAECgQJBAABLgAFFAYJGQAdAOIWAA==.',
Ke='Keeflo:BAAALgADCgkJEgAAAA==.Kelisii:BAAALgAFFAMJBAAAAA==.Keloenivas:BAAALgADCggJEQAAAA==.Kelomage:BAAALgAECgEJAQAAAA==.Ketaza:BAAALgAECgEJAQAAAA==.Keyash:BAAALgADCgIJAgAAAA==.',
Kh='Khyle:BAAALgADCgEJAQABLgADCgcJEAAGAAAAAA==.',
Ki='Kibblebits:BAABLgAECn8aAAIgAAcJbwOMWQCQAAAgAAcJbwOMWQCQAAAAAA==.Kijanajr:BAAALgAECgIJAgAAAA==.Kitch:BAAALgADCggJDAAAAA==.Kitheros:BAAALgADCgcJBwAAAA==.Kittun:BAAALgADCgEJAQAAAA==.',
Kl='Klay:BAABLgAECn87AAQZAAkJ3yWRAABrAwAZAAkJ3yWRAABrAwACAAMJug1pNABgAAABAAIJtQKSngBGAAAAAA==.Klutch:BAAALgADCgIJAgAAAA==.',
Km='Kmarti:BAECLgAFFH8OAAIPAAQJaRGFOwAYAQAPAAQJaRGFOwAYAQAuAAQKfyYAAw8ACQklHmUhAIkCAA8ACQklHmUhAIkCABIAAgn/CwFgAGIAAAAA.',
Ko='Koivath:BAAALgADCgkJEQAAAA==.Konradevoker:BAAALgAFFAEJAgABLgAECgkJKwAFAFUeAA==.Konradlock:BAABLgAECn8rAAMFAAkJVR6YBgBVAwAFAAkJVR6YBgBVAwANAAIJVxk5TQCGAAAAAA==.Konradrogue:BAABLgAECn8xAAMmAAkJuB6tAABiAwAmAAkJoR6tAABiAwAVAAcJYxraHQAPAgABLgAECgkJKwAFAFUeAA==.Konradwar:BAABLgAECn8XAAMCAAYJNx79EgBzAQACAAYJZhj9EgBzAQABAAQJpRbCbgD8AAABLgAECgkJKwAFAFUeAA==.Koros:BAAALgAECgQJBAAAAA==.Kosmicknight:BAABLgAECn8hAAIUAAgJ7xURUADAAQAUAAgJ7xURUADAAQAAAA==.',
Kr='Krathös:BAAALgAECgYJDQAAAA==.Krimzin:BAAALgAECgEJAQABLgAFFAUJFgAIAHwgAA==.Kromak:BAAALgAECgQJBAAAAA==.',
Ku='Kunfoopizza:BAAALgAECgQJCQAAAA==.Kuulibah:BAAALgADCgEJAQABLgADCgMJAwAGAAAAAA==.Kuulibarr:BAAALgADCgMJAwAAAA==.',
Kw='Kwarr:BAACLgAFFH8TAAIhAAUJaxHjIABCAQAhAAUJaxHjIABCAQAuAAQKfyIAAiEACAnlH4MQALQCACEACAnlH4MQALQCAAEuAAUUBQkaABoAdRQA.',
Ky='Kyaila:BAAALgADCgEJAQAAAA==.Kynaragon:BAABLgAECn8lAAMgAAcJfSaVGABEAgAgAAYJZSaVGABEAgAEAAQJ0CSqYwAmAQABLgAFFAUJBgAEACwfAA==.Kyrimmon:BAAALgAECgEJAQAAAA==.',
La='Lalii:BAAALgAECgEJAwAAAA==.Lallypop:BAAALgAECgcJEQAAAA==.Lammoth:BAAALgAECgEJAgAAAA==.Lanthein:BAAALgAECgEJAQABLgAFFAcJFgAaAGkZAA==.Laraela:BAAALgADCgEJAQAAAA==.Largehusband:BAAALgAECgEJAQAAAA==.Larkindas:BAAALgAECgMJBAAAAA==.Layil:BAAALgADCgYJBwAAAA==.',
Le='Leafu:BAABLgAECn8UAAMJAAUJEhvyPwDpAAAJAAMJ5BryPwDpAAAOAAUJ9AmXZACwAAABLgAECggJJwAbAGwdAA==.Leasin:BAABLgAECn8nAAIbAAgJbB0GEgAoAgAbAAgJbB0GEgAoAgAAAA==.Leathle:BAAALgADCgkJEAAAAA==.Leepa:BAAALgAECgcJDgAAAA==.Leesta:BAAALgAECgEJAgAAAA==.Lepp:BAAALgAECgEJAQAAAA==.Lexslaner:BAAALgADCgYJCQAAAA==.',
Li='Lighthusk:BAABLgAECn8cAAMkAAkJKx8sBwDpAgAkAAkJKx8sBwDpAgAbAAQJMwYAWACIAAABLgAECgkJHAAkACsfAA==.Lightreaper:BAAALgAECgEJAQAAAA==.Likeans:BAAALgAECgEJAQAAAA==.Liliauna:BAABLgAECn8nAAIFAAkJ9RPVNQD1AQAFAAkJ9RPVNQD1AQAAAA==.Lilibejeane:BAAALgAECgYJBwABLgAECgkJLQASAFIUAA==.Lilithalen:BAACLgAFFH8OAAIkAAQJoxGJEQAcAQAkAAQJoxGJEQAcAQAuAAQKfy8AAiQACAnmGegVAC0CACQACAnmGegVAC0CAAAA.Lilmymy:BAAALgAECgIJAgAAAA==.Lilshimer:BAABLgAECn8XAAMFAAYJ4BmeVgDEAQAFAAYJ4BmeVgDEAQAMAAIJdQMoIQBtAAAAAA==.Lilsquirtboy:BAACLgAFFH8TAAIUAAMJ8ibbOgBcAQAUAAMJ8ibbOgBcAQAuAAQKfzMAAxQACQnzI0cJABcDABQACQnzI0cJABcDACIAAQmZCcdNABsAAAAA.Linithara:BAAALgAECgUJBQABLgAFFAQJDgAkAKMRAA==.Litterling:BAAALgAECgcJDAAAAA==.Lizardbird:BAAALgAECgQJBwAAAA==.Lizzi:BAAALgADCgcJBgAAAA==.',
Lo='Lockersz:BAAALgAECgQJCAABLgAFFAUJCQAYAAMNAA==.Lockitt:BAABLgAECn8dAAIFAAkJ8w8mXQCxAQAFAAkJ8w8mXQCxAQAAAA==.Loram:BAAALgAECgEJAQAAAA==.Lostangel:BAAALgADCgMJAwAAAA==.Lostgrip:BAAALgAECgQJBgAAAA==.',
Lu='Lucthedk:BAABLgAECn8aAAIUAAYJThLPngAYAQAUAAYJThLPngAYAQAAAA==.Luk:BAAALgADCgYJBgAAAA==.Lukis:BAAALgAECgEJAQAAAA==.Lumario:BAAALgADCgEJAQAAAA==.Lunarpriest:BAAALgAECgEJAQAAAA==.Lunitari:BAAALgADCggJCAAAAA==.Lunkbeck:BAAALgAECgcJEQAAAA==.Luva:BAAALgADCgcJEQAAAA==.Luxriel:BAAALgAECgQJBQAAAA==.',
Ly='Lyio:BAAALgAECgUJDAAAAA==.',
Ma='Madmandeath:BAAALgADCgQJAwAAAA==.Magicmegan:BAAALgAECgEJAgABLgAFFAEJAQAGAAAAAA==.Mahlanas:BAAALgAECgYJDgAAAA==.Maki:BAABLgAFFH8MAAIUAAMJsRa3egDoAAAUAAMJsRa3egDoAAAAAA==.Maladin:BAABLgAECn8ZAAMHAAgJqwnIHQANAQAHAAgJqwnIHQANAQADAAMJQwNuPQFTAAAAAA==.Malvean:BAAALgADCgcJCgAAAA==.Mamajoy:BAAALgADCgMJBgAAAA==.Maravilla:BAABLgAECn8WAAIQAAgJhQ1XJQABAQAQAAgJhQ1XJQABAQAAAA==.Marceline:BAABLgAECn8VAAIIAAkJORGTNAD0AQAIAAkJORGTNAD0AQAAAA==.Markuspapa:BAAALgAECgQJBAABLgAFFAYJGQAdAOIWAA==.Marlowe:BAAALgAECgcJDQAAAA==.Marremer:BAABLgAECn8YAAMiAAcJJQ8fJAAgAQAiAAUJnhMfJAAgAQAjAAcJKwRZIACVAAAAAA==.',
Mc='Mckicky:BAAALgAECgYJDwAAAA==.',
Me='Mechafire:BAAALgADCgYJBgAAAA==.Melanius:BAACLgAFFH8NAAIeAAUJaBXaEABjAQAeAAUJaBXaEABjAQAuAAQKfzUAAx4ACQkaJcQAALEDAB4ACQkaJcQAALEDAB8AAQkeD6oiADUAAAAA.Melliex:BAAALgADCgMJBgAAAA==.Melodras:BAABLgAECn8eAAMkAAgJrhIpJgB9AQAkAAgJrhIpJgB9AQAdAAIJkgZqTgBXAAAAAA==.Memelord:BAAALgAECgQJCgAAAA==.Merce:BAAALgADCgEJAQAAAA==.Metalock:BAAALgADCgcJCwAAAA==.Mewalina:BAAALgADCgQJBAAAAA==.',
Mi='Mirajen:BAAALgADCgMJAwAAAA==.Mirukoo:BAAALgAECgQJBAAAAA==.Misclick:BAAALgADCgQJBAAAAA==.Misconduct:BAACLgAFFH8IAAISAAIJ6g6+GgCIAAASAAIJ6g6+GgCIAAAuAAQKfyEAAhIACAkkICcKAGkCABIACAkkICcKAGkCAAAA.Missile:BAAALgAECgIJAgAAAA==.Mistywaters:BAAALgAECgEJAgAAAA==.Mittyy:BAAALgADCgYJBwAAAA==.',
Mo='Moomist:BAAALgAECgcJCAAAAA==.Moosifer:BAAALgAECgEJAQAAAA==.Mornintreant:BAAALgADCgMJAwAAAA==.Morukhai:BAAALgADCgcJCAAAAA==.Mousekewitzk:BAAALgAECgQJAwAAAA==.Movarth:BAAALgADCgkJCQAAAA==.',
Mu='Mujer:BAAALgAECgEJAQAAAA==.Mungas:BAAALgADCgUJBgAAAA==.Murlloc:BAAALgADCgcJBgAAAA==.',
My='Myrathia:BAABLgAFFH8GAAIEAAIJmAQTVgBhAAAEAAIJmAQTVgBhAAAAAA==.Myrcella:BAAALgAECgQJBQAAAA==.',
['Má']='Máximodécimo:BAAALgAECgMJDAAAAA==.',
Na='Nahemah:BAAALgAECgIJAwABLgAECggJFAAPAI8WAA==.Nahtan:BAABLgAECn8nAAIIAAcJXhRqWgB8AQAIAAcJXhRqWgB8AQAAAA==.Nahwe:BAAALgADCgUJBQAAAA==.Narrsul:BAABLgAECn8XAAIFAAYJ6RJycwB4AQAFAAYJ6RJycwB4AQAAAA==.Nattyg:BAAALgAECgYJEAAAAA==.Naves:BAAALgADCgYJCAAAAA==.',
Ne='Nebbia:BAAALgAECgEJAwAAAA==.Nekamsi:BAAALgAECgEJAQAAAA==.Nereza:BAAALgADCgUJDAAAAA==.Nevermorte:BAAALgAECgYJBgAAAA==.',
Nf='Nfggolden:BAAALgAECgcJAwAAAA==.',
Ni='Nightforday:BAABLgAECn9OAAIUAAkJ5BxOFAC7AgAUAAkJ5BxOFAC7AgAAAA==.Niko:BAAALgAECgQJDQAAAA==.Nineve:BAAALgADCgIJAgABLgADCgkJCwAGAAAAAA==.',
No='Noknani:BAAALgADCgUJBgAAAA==.Nokx:BAAALgAECgEJAQAAAA==.Nool:BAAALgADCgcJCQAAAA==.Norch:BAAALgADCgMJBAAAAA==.Nostranova:BAAALgAECgEJAQAAAA==.Novà:BAAALgADCgMJAwAAAA==.',
Ny='Nyriand:BAAALgADCgQJBAAAAA==.Nyxiia:BAAALgADCgIJAgAAAA==.',
Ob='Obalon:BAAALgAECgEJAQAAAA==.',
Oe='Oedipuss:BAAALgADCgUJBQABLgADCgYJCAAGAAAAAA==.',
Og='Ogora:BAAALgADCgIJAgAAAA==.',
Oh='Ohkayboomer:BAABLgAFFH8GAAMEAAQJmgtMRACTAAAEAAMJjQNMRACTAAAgAAIJ2QE/PQBOAAAAAA==.Ohkaylocker:BAAALgAECggJDgAAAA==.',
Ok='Okktral:BAAALgAFFAIJAgAAAA==.Oktraal:BAAALgAECgEJAQABLgAFFAIJAgAGAAAAAA==.',
Oo='Oontanx:BAAALgADCgcJCQAAAA==.Ooups:BAABLgAECn8gAAIJAAgJcBT5HwCVAQAJAAgJcBT5HwCVAQAAAA==.',
Op='Ophysia:BAABLgAECn8kAAIDAAgJQB3PLgAsAgADAAgJQB3PLgAsAgAAAA==.',
Or='Orangecage:BAABLgAECn8yAQMgAAkJlSaUAACHAwAgAAkJlSaUAACHAwAEAAIJfwYmswBeAAAAAA==.Orkcansas:BAAALgAFFAEJAQAAAA==.Orong:BAAALgAECgMJBAAAAA==.',
Os='Osla:BAAALgAECgkJEAAAAA==.Osrsfemale:BAAALgAECgIJAgAAAA==.',
Ov='Overlooker:BAAALgAECgQJBwAAAA==.',
Ox='Oxazine:BAACLgAFFH8HAAITAAMJHQ1OLQC8AAATAAMJHQ1OLQC8AAAuAAQKfykAAxMACQlKGd0UACoCABMACQlKGd0UACoCACEABQmOA5OWAHwAAAAA.',
Pa='Paapineau:BAABLgAECn8jAAImAAgJ2QizDQA5AQAmAAgJ2QizDQA5AQAAAA==.Packel:BAAALgADCgEJAQABLgAECgkJMQAQAHETAA==.Packs:BAAALgAECgEJAQABLgAECgkJMQAQAHETAA==.Palladias:BAAALgAECgQJBgAAAA==.Pally:BAAALgADCgIJAgAAAA==.Partysnaxx:BAAALgADCgcJBwAAAA==.',
Pc='Pcm:BAAALgAFFAEJAQABLgAFFAEJAQAGAAAAAA==.',
Pe='Peefmajeef:BAAALgADCgIJAgAAAA==.Peony:BAAALgADCgQJBAAAAA==.Pepperjack:BAAALgAECgQJBwAAAA==.Petshellkek:BAACLgAFFH8YAAMUAAcJxSI6BQCuAQAUAAcJxSI6BQCuAQAjAAEJfBYkGwBVAAAuAAQKfxcAAhQACAktI34UAAADABQACAktI34UAAADAAAA.Pewpeew:BAAALgAECgUJDQAAAA==.',
Ph='Phantomclone:BAABLgAECn8UAAIWAAYJYR45JAC1AQAWAAYJYR45JAC1AQAAAA==.Phantomghoul:BAAALgADCgEJAQAAAA==.Phantomwar:BAAALgAECgIJAgAAAA==.Phantomzz:BAAALgAECgEJAQAAAA==.Phaté:BAAALgADCgEJAQAAAA==.Pheonixxwolf:BAAALgAECgYJDgAAAA==.Pherc:BAAALgADCgcJBwAAAA==.Phillyblunt:BAABLgAECn8aAAMhAAcJURNHMQDBAQAhAAcJURNHMQDBAQATAAEJDQcjiwAtAAAAAA==.Philomena:BAAALgADCgEJAQAAAA==.Phløw:BAAALgADCgUJDAAAAA==.',
Pi='Picaroxy:BAAALgADCgUJBQAAAA==.Piyo:BAAALgAECgMJAwABLgAECgkJMQAQAHETAA==.',
Pl='Plaguekitten:BAAALgAECgEJAQAAAA==.',
Po='Poisonblade:BAAALgAECgEJAgAAAA==.Pollidi:BAAALgAECgQJBQAAAA==.Poolius:BAAALgAECgQJEAAAAA==.Popadot:BAAALgAECgkJBQAAAA==.Porfinne:BAAALgAECgMJBgAAAA==.',
Pr='Praedor:BAAALgADCgUJBQAAAA==.Preza:BAAALgADCgIJAgAAAA==.Priestymon:BAACLgAFFH8HAAIdAAIJ3htCMACYAAAdAAIJ3htCMACYAAAuAAQKfyYAAx0ACAkOH4IKAJECAB0ACAkOH4IKAJECABsABQnxFHo6AAYBAAEuAAUUBgkVAAEACR8A.Prober:BAAALgADCgUJBQAAAA==.Producer:BAAALgAECgEJAQAAAA==.Protato:BAAALgAECgYJCwAAAA==.Prowaifu:BAAALgAECgYJDAAAAA==.Prowess:BAAALgADCggJFAAAAA==.Prîestitute:BAAALgADCgYJCQAAAA==.',
Pu='Purger:BAAALgADCgYJCgAAAA==.Pussinbooger:BAAALgAECgEJAQAAAA==.Puyo:BAABLgAECn8xAAIQAAkJcRN4EQCyAQAQAAkJcRN4EQCyAQAAAA==.Puyyoo:BAAALgADCgcJDwABLgAECgkJMQAQAHETAA==.',
Pw='Pwarr:BAACLgAFFH8VAAIZAAUJbBp1DQA0AQAZAAUJbBp1DQA0AQAuAAQKfycAAxkACAnrH70KAGUCABkABwnXIb0KAGUCAAIACAm1E6UTAKwBAAEuAAUUBQkaABoAdRQA.',
Py='Pyrofox:BAAALgADCgEJAQAAAA==.',
Qw='Qwarr:BAACLgAFFH8aAAMaAAUJdRRUJAAVAQAaAAUJdRRUJAAVAQAfAAIJWQnfBgChAAAuAAQKfzwAAxoACQnWIvkFAOYCABoACQnWIvkFAOYCAB8ABglCHu8PAN0BAAAA.',
Ra='Raeljin:BAAALgAECgkJBgAAAA==.Rafoen:BAABLgAFFH8FAAIVAAIJ2hPvLACQAAAVAAIJ2hPvLACQAAAAAA==.Rakrur:BAAALgADCgEJAQAAAA==.Ramsay:BAAALgAECgMJAwAAAA==.Ranee:BAAALgAECgMJBAAAAA==.Rathorn:BAAALgADCgYJDAAAAA==.Ravnur:BAAALgADCgkJCQAAAA==.Rawrr:BAAALgAECgEJAQAAAA==.Raxsan:BAAALgAFFAMJBAAAAA==.Raydanbalor:BAAALgAECgUJBQABLgAECgcJGAAiACUPAA==.Rayennagrom:BAABLgAECn8bAAMnAAcJpQZuCADgAAAnAAcJpQZuCADgAAALAAEJAAABbQEAAAAAAA==.Razkko:BAAALgADCgUJBQAAAA==.',
Rd='Rdru:BAAALgADCgcJBwABLgAECgYJEAAGAAAAAA==.',
Re='Redpumpkin:BAAALgADCgMJAwAAAA==.Redsonja:BAAALgADCgcJDQAAAA==.Rel:BAAALgADCgYJBgAAAA==.Reneana:BAAALgAECgUJAgAAAA==.Respectisluv:BAABLgAECn8mAAIXAAgJfBDtGwCvAQAXAAgJfBDtGwCvAQAAAA==.Restbo:BAAALgAFFAMJAwAAAA==.Rexcor:BAAALgAECgQJDgAAAA==.',
Rh='Rhulad:BAAALgADCggJCAAAAA==.',
Ri='Riaeline:BAAALgAECgQJBgAAAA==.Richardluis:BAAALgAECgYJCwAAAA==.Rinehardtt:BAAALgAFFAEJAQAAAA==.Ripchan:BAAALgADCgIJAgABLgAFFAUJGAAhAMYSAA==.Ripchi:BAAALgAECgcJBwABLgAFFAUJGAAhAMYSAA==.Ripcurrent:BAAALgAECgUJBQAAAA==.Ripheals:BAACLgAFFH8YAAMhAAUJxhJ3IgA6AQAhAAUJxhJ3IgA6AQATAAEJFghTSQA8AAAuAAQKfzcAAyEACQkVHQEcAFECACEACQkVHQEcAFECABMABQlUGhlBAEUBAAAA.Riplee:BAAALgADCgYJCwABLgAFFAUJGAAhAMYSAA==.Rit:BAAALgAECgIJAgAAAA==.Rivër:BAABLgAECn8YAAIDAAkJqxv6PwAmAgADAAkJqxv6PwAmAgAAAA==.',
Ro='Robbell:BAABLgAECn8bAAIIAAgJaxkLIABFAgAIAAgJaxkLIABFAgAAAA==.Rockd:BAAALgAECgcJCwAAAA==.Rogueflame:BAAALgAECgcJDwAAAA==.Rootsie:BAABLgAECn8dAAINAAcJgQu2EwD2AAANAAcJgQu2EwD2AAAAAA==.Roselynn:BAABLgAECn8sAAIEAAkJgBvdDwC5AgAEAAkJgBvdDwC5AgAAAA==.',
Rs='Rsolbes:BAAALgADCgUJBQAAAA==.',
Ru='Ruerl:BAABLgAECn8YAAMHAAkJ8g0UIwDvAAAHAAYJGwoUIwDvAAADAAkJPgrxyADeAAAAAA==.Ruffandready:BAAALgADCgMJAwAAAA==.Rumblies:BAABLgAECn8WAAIOAAgJCxpTHAAPAgAOAAgJCxpTHAAPAgAAAA==.Runetusk:BAAALgADCgEJAQABLgAECgYJDQAGAAAAAA==.Rungin:BAAALgADCgEJAQAAAA==.Russopp:BAAALgADCgEJAQAAAA==.',
Sa='Saars:BAAALgADCgYJBgAAAA==.Samchan:BAAALgAECgcJEwAAAA==.Sanatharia:BAAALgAECgYJDAAAAA==.Saneatey:BAAALgAECgUJCwAAAA==.Sassibelle:BAAALgAECgUJBQAAAA==.Satanskidney:BAAALgAECgIJAgAAAA==.Sathenset:BAACLgAFFH8WAAIaAAcJaRmmCwD7AQAaAAcJaRmmCwD7AQAuAAQKfxUAAx8ACAnLGFARAMoBAB8ABwmsFlARAMoBABoABAmrEjlDANQAAAAA.Savara:BAAALgAECgMJAwABLgAFFAcJFgAaAGkZAA==.',
Sc='Scandium:BAABLgAECn8yAAIMAAkJKiBvAgCQAgAMAAkJKiBvAgCQAgAAAA==.Scrembiblion:BAABLgAECn8wAAMLAAkJLiK6DAD/AgALAAkJLiK6DAD/AgAcAAIJvh7UCgC2AAAAAA==.',
Sd='Sdhoscillate:BAAALgAFFAEJAQAAAA==.',
Se='Seagulpunchr:BAAALgADCgYJCgAAAA==.Seesh:BAACLgAFFH8KAAIBAAQJLiD1BgB+AQABAAQJLiD1BgB+AQAuAAQKfxgAAgEACQnSJBQDAH8DAAEACQnSJBQDAH8DAAAA.Seidr:BAAALgAECgEJAQAAAA==.Senseitional:BAAALgAECggJEgABLgAECgkJLwAFAGsZAA==.Sentarr:BAABLgAFFH8VAAIZAAUJrSFACwBUAQAZAAUJrSFACwBUAQAAAA==.Septhera:BAAALgAFFAEJAgAAAA==.',
Sh='Shadewither:BAAALgADCgQJBAAAAA==.Shadey:BAAALgAECgEJAQAAAA==.Shadeyheals:BAAALgAECggJEQAAAA==.Shadowxcraft:BAAALgAECgcJDQAAAA==.Shadrelin:BAAALgADCgEJAgAAAA==.Shadygnome:BAAALgAECgYJBAAAAA==.Shaqler:BAAALgAECgMJBAAAAA==.Shecks:BAAALgADCgcJCAAAAA==.Shelandria:BAAALgAECgQJBgAAAA==.Sherwild:BAABLgAECn8YAAIEAAgJxyHwCgDqAgAEAAgJxyHwCgDqAgAAAA==.Shinara:BAABLgAECn8mAAIVAAgJ9RhDEgD+AQAVAAgJ9RhDEgD+AQAAAA==.Shiverchill:BAAALgAECgcJCQAAAA==.Shizznoint:BAAALgADCgMJAwAAAA==.Shnipishnap:BAABLgAECn+cAAMhAAkJHiPWAACgAwAhAAkJHiPWAACgAwATAAkJuSZAAACPAwAAAA==.Shroomjuicee:BAABLgAECn85AAIdAAkJxBvyBwDdAgAdAAkJxBvyBwDdAgAAAA==.Shyi:BAAALgADCgYJBgAAAA==.Shìlo:BAAALgAECgUJBwAAAA==.Shìlò:BAAALgAECgQJBAAAAA==.',
Si='Sindaemon:BAACLgAFFH8HAAIPAAMJdRuJIwCzAAAPAAMJdRuJIwCzAAAuAAQKfyMAAg8ACAn2IWQUAN0CAA8ACAn2IWQUAN0CAAAA.Sindrina:BAAALgAECgIJAgAAAA==.',
Sk='Skedaddle:BAAALgAECgQJBgAAAA==.Skelstone:BAAALgADCgYJBgAAAA==.Skädoosh:BAAALgAECgcJDgAAAA==.',
Sl='Slapshappy:BAABLgAECn8vAAIDAAgJ/BciUQC9AQADAAgJ/BciUQC9AQAAAA==.Sloptop:BAAALgAECgMJAwAAAA==.Slowfall:BAAALgADCgcJCwAAAA==.',
Sm='Smithssinger:BAAALgAECgUJBQAAAA==.Smokin:BAAALgAECgYJDwAAAA==.Smoothg:BAAALgAECgMJAwAAAA==.',
Sn='Snowjor:BAAALgADCgEJAQAAAA==.Snyx:BAAALgADCgUJBQAAAA==.',
So='Solaríus:BAAALgADCgMJAwAAAA==.Soldanas:BAAALgADCgEJAQAAAA==.Solomus:BAAALgAECgQJCQAAAA==.Sorceroid:BAAALgADCgIJAgAAAA==.',
Sp='Spheaddin:BAAALgAECgEJAQAAAA==.Spiritbomb:BAABLgAECn8lAAIPAAkJsRrXHgBHAgAPAAkJsRrXHgBHAgAAAA==.Spytime:BAAALgAECgcJDQAAAA==.',
Ss='Ssjchezzy:BAAALgAECgcJDgAAAA==.Ssmeltn:BAAALgAECgYJDQAAAA==.',
St='Staranaria:BAAALgADCgUJBQAAAA==.Steinberg:BAAALgADCgEJAQAAAA==.Stelltrain:BAAALgAECgQJBAAAAA==.Stnaprednu:BAACLgAFFH8IAAIDAAMJIw9XXQDUAAADAAMJIw9XXQDUAAAuAAQKfxoAAgMACAktGYA/APABAAMACAktGYA/APABAAAA.Stoploss:BAAALgADCgEJAQAAAA==.Stormiee:BAABLgAECn8XAAIhAAkJ2Q7cMwDHAQAhAAkJ2Q7cMwDHAQABLgAECggJHgAEAFITAA==.Stormr:BAAALgAECgQJBAAAAA==.Stormroid:BAAALgAECgYJCgAAAA==.Stormxwolf:BAAALgAECgYJDQAAAA==.Strangulate:BAAALgAECgQJBQAAAA==.Stripez:BAAALgADCgUJBwAAAA==.Stumpvee:BAAALgADCgMJAwAAAA==.',
Su='Sunmx:BAABLgAFFH8KAAIBAAMJyyDKHwAdAQABAAMJyyDKHwAdAQAAAA==.Sunmxqwe:BAAALgAECgEJAQAAAA==.Superdark:BAAALgAECgMJBgAAAA==.Surgah:BAAALgADCgEJAQAAAA==.',
Sw='Swurves:BAAALgAFFAIJBAAAAA==.',
Sy='Sybrooker:BAAALgADCgQJBQAAAA==.',
Ta='Tadpole:BAAALgAECgcJBwAAAA==.Taedrum:BAAALgAECgYJCgAAAA==.Taerror:BAACLgAFFH8XAAIkAAYJwxsGAwAeAgAkAAYJwxsGAwAeAgAuAAQKfzEABCQACQmyI38AAK8DACQACQmyI38AAK8DAB0ABAmIGFc5AAQBABsAAQktB5B/ACoAAAAA.Tahkon:BAAALgAECgYJCwAAAA==.Tahmtan:BAAALgADCgcJEAAAAA==.Talegos:BAAALgAECgQJBAAAAA==.Talonfel:BAAALgADCgcJCwABLgAFFAMJDQAOAMkdAA==.Talonflight:BAAALgAECggJDgABLgAFFAMJDQAOAMkdAA==.Talonstryke:BAACLgAFFH8NAAIOAAMJyR23IgADAQAOAAMJyR23IgADAQAuAAQKfz8AAg4ACQl0I/ICAHwDAA4ACQl0I/ICAHwDAAAA.Taloran:BAAALgADCgkJEwAAAA==.Talzul:BAAALgADCgMJAwAAAA==.Tanarious:BAAALgADCgQJBAAAAA==.Taytonar:BAABLgAECn8tAAIHAAcJUwooIgDnAAAHAAcJUwooIgDnAAAAAA==.',
Te='Teamocil:BAAALgAECgEJAwAAAA==.Teefa:BAAALgAECgYJCwAAAA==.Tehrror:BAAALgADCgMJAwAAAA==.Tehyra:BAAALgAECgIJAgAAAA==.Tenths:BAAALgADCgEJAQAAAA==.Terak:BAAALgAECgEJAQAAAA==.Terrisman:BAAALgAECgYJBgAAAA==.Testsubjectz:BAAALgAFFAUJAQAAAA==.Tevers:BAAALgADCgcJDAAAAA==.',
Th='Thane:BAAALgADCgMJAwAAAA==.Thaumium:BAAALgADCgEJAQAAAA==.Theenforcer:BAABLgAECn8hAAIDAAgJJw5/ewBcAQADAAgJJw5/ewBcAQAAAA==.Theguyfurry:BAAALgADCgcJCwAAAA==.Thidwick:BAAALgAECgQJCAABLgAECgkJLwAFAGsZAA==.Thingtwø:BAAALgAECgMJAwAAAA==.Thirdryker:BAAALgADCgIJAgAAAA==.Thistle:BAAALgAECgQJBAAAAA==.Thorissa:BAABLgAECn8YAAINAAgJzA0PEwCzAQANAAgJzA0PEwCzAQAAAA==.Thäne:BAABLgAECn8pAAIUAAcJuBMfcQBuAQAUAAcJuBMfcQBuAQAAAA==.',
Ti='Tibbzz:BAAALgAECgUJBQAAAA==.Tickletorque:BAAALgAECgcJEQABLgAFFAMJEwAUAPImAA==.Tikimon:BAAALgADCgIJAgAAAA==.Tiles:BAAALgAECgIJAwAAAA==.Timojj:BAAALgAECgEJAwAAAA==.Tinglu:BAAALgADCgcJCQAAAA==.Tinkk:BAAALgAECgcJEQAAAA==.Titø:BAAALgAECgYJCwAAAA==.',
To='Tomorrow:BAACLgAFFH8PAAILAAQJwxslPgBRAQALAAQJwxslPgBRAQAuAAQKfxoAAgsACAkpHvlOAEoCAAsACAkpHvlOAEoCAAAA.Topdog:BAAALgAECgUJBQAAAA==.Topzee:BAAALgAECgQJBwAAAA==.Torquin:BAAALgADCgMJAwAAAA==.Tottytotems:BAAALgADCgcJDAAAAA==.Touchmablade:BAAALgADCgQJBAAAAA==.',
Tr='Traylo:BAABLgAECn8mAAMIAAcJ8RPzUgCRAQAIAAcJ8RPzUgCRAQAYAAIJ/QCtigAxAAAAAA==.Treysong:BAAALgADCgMJAwAAAA==.',
Tu='Turkeymm:BAAALgADCgMJAwAAAA==.',
Tv='Tvak:BAABLgAECn8fAAIDAAkJICCrKQBDAgADAAkJICCrKQBDAgAAAA==.',
Tw='Twopump:BAABLgAECn8sAAIDAAkJBw6yWgCkAQADAAkJBw6yWgCkAQAAAA==.',
Ty='Tygrarelea:BAAALgAECgEJAQAAAA==.Tynan:BAAALgADCgUJCgAAAA==.Tyrah:BAAALgADCgQJBQAAAA==.',
Ul='Ulinova:BAABLgAECn8bAAIoAAgJSRItCACfAQAoAAgJSRItCACfAQAAAA==.',
Up='Uppercut:BAAALgAECgEJAQAAAA==.',
Ur='Uroro:BAAALgAFFAIJAwAAAA==.',
Uu='Uu:BAABLgAFFH8PAAMJAAMJOQJvPgCMAAAJAAMJYAFvPgCMAAAWAAIJUgKHMABbAAAAAA==.',
Uz='Uzas:BAAALgAECgMJAwAAAA==.',
Va='Vaehi:BAAALgAECgEJAQAAAA==.Vaiden:BAAALgADCgEJAQAAAA==.Vainqueur:BAABLgAECn8WAAIfAAgJkBc2BQD+AQAfAAgJkBc2BQD+AQAAAA==.Valoroso:BAAALgAECgQJBAAAAA==.Vanarios:BAAALgAECgEJAgAAAA==.Vanderdemon:BAAALgAECgcJCQAAAA==.Vanderius:BAAALgAECgEJAQAAAA==.Vanderpal:BAAALgADCggJBgAAAA==.Vanec:BAAALgADCgMJAwAAAA==.Varm:BAAALgAECgEJAQAAAA==.Vasarian:BAAALgAECgEJAQAAAA==.Vayan:BAAALgADCgYJDAAAAA==.',
Ve='Veidima:BAAALgAECgQJBgAAAA==.Veigar:BAAALgADCgYJBgAAAA==.Velathrus:BAAALgADCgEJAQAAAA==.Velinamue:BAAALgAECgEJAQAAAA==.Velion:BAAALgAECgIJAwAAAA==.Velyine:BAAALgADCgQJBAAAAA==.Verzweifeln:BAAALgAECgYJDwAAAA==.Vesenya:BAAALgAECgIJAgAAAA==.Veyez:BAAALgADCgkJDAAAAA==.',
Vg='Vgx:BAAALgAECgEJAQAAAA==.',
Vh='Vhels:BAAALgADCgUJBQAAAA==.Vhyrix:BAAALgAECgQJBQAAAA==.',
Vi='Viantel:BAAALgAECgYJEAAAAA==.Vielitre:BAAALgADCgMJAwAAAA==.Viklicious:BAAALgADCgkJCQAAAA==.Vinarn:BAABLgAECn88AAMUAAkJQA8NSwDPAQAUAAkJ2A4NSwDPAQAjAAYJAg0ACgAzAQAAAA==.Vinyls:BAAALgAECgMJBAAAAA==.Viridias:BAAALgADCgIJAgAAAA==.Viridius:BAAALgAECgUJDAAAAA==.Virindi:BAAALgAECgEJAQAAAA==.Vishouspayne:BAAALgAECgMJCAAAAA==.',
Vo='Voidburn:BAAALgADCgUJBQAAAA==.',
Vr='Vrogar:BAABLgAFFH8HAAIXAAMJzgnfHADXAAAXAAMJzgnfHADXAAAAAA==.',
Vy='Vyntage:BAABLgAECn8VAAITAAkJ8Qo4MABlAQATAAkJ8Qo4MABlAQAAAA==.',
['Vä']='Väelün:BAABLgAECn8vAAIPAAcJPBYTSACWAQAPAAcJPBYTSACWAQABLgAECgkJJwAQABIRAA==.',
['Vî']='Vîgo:BAAALgADCgEJAQAAAA==.',
Wa='Wachoosh:BAAALgAECgYJDwAAAA==.Wackamoose:BAABLgAECn8hAAQCAAcJRB3wEADKAQACAAcJRB3wEADKAQAZAAQJ7g51MADAAAABAAIJmgdjlgBnAAAAAA==.Wagoogusmay:BAAALgAECgEJAQAAAA==.Waidmanns:BAACLgAFFH8IAAIIAAQJLQ+4UADfAAAIAAQJLQ+4UADfAAAuAAQKfy0AAwgACQk6HO0dAFICAAgACQk6HO0dAFICABcABQkuE94xAAwBAAAA.Walkinredflg:BAAALgADCgYJBgAAAA==.Walvet:BAABLgAECn8aAAIdAAkJfRr4DACBAgAdAAkJfRr4DACBAgAAAA==.Warc:BAAALgADCgUJBQAAAA==.Wargramps:BAAALgADCgQJBAAAAA==.Warrioo:BAAALgADCgMJAwABLgAECgcJBwAGAAAAAA==.',
We='Weather:BAAALgADCgUJBQABLgAECggJEwAGAAAAAA==.Weelad:BAAALgADCgkJFAAAAA==.Weldord:BAABLgAECn9DAAIIAAgJ2w3yWgB7AQAIAAgJ2w3yWgB7AQAAAA==.',
Wh='Whatorne:BAAALgAECgUJBgAAAA==.Whatyamean:BAAALgADCgQJBAAAAA==.Whiskeytaur:BAAALgADCgYJBgAAAA==.',
Wi='Wickedchick:BAABLgAECn8eAAIgAAYJcw4UQADxAAAgAAYJcw4UQADxAAAAAA==.Willock:BAAALgAECgUJCgAAAA==.Willowknight:BAAALgAECgMJAwAAAA==.',
Wo='Wolvareene:BAAALgADCgcJBwAAAA==.',
Wr='Wrenn:BAAALgAFFAEJAQAAAA==.Wrongknight:BAAALgAECgQJDAAAAA==.Wrongname:BAAALgAECgUJEgAAAA==.',
Xa='Xalthérion:BAAALgAECgMJAwAAAA==.',
Xe='Xeruu:BAAALgADCgUJBQAAAA==.',
Xo='Xolan:BAACLgAFFH8FAAIEAAIJKQ20GwCOAAAEAAIJKQ20GwCOAAAuAAQKfx0AAgQACAkQGtYkACYCAAQACAkQGtYkACYCAAAA.',
Xp='Xprophet:BAABLgAECn8UAAIBAAYJvAQQYQC3AAABAAYJvAQQYQC3AAAAAA==.',
Xu='Xunghuai:BAAALgAECgEJAQAAAA==.',
Xw='Xw:BAAALgADCgYJCwAAAA==.',
['Xß']='Xß:BAAALgAECgYJBgAAAA==.',
Ye='Yemonyunter:BAAALgADCgUJBQAAAA==.Yesyesyes:BAAALgADCgIJAgAAAA==.',
Yo='Yogsothoth:BAEBLgAECn8hAAMIAAgJgxQhTwCcAQAIAAgJiBMhTwCcAQAXAAYJjBBiFgBjAQAAAA==.Yooloakala:BAAALgADCggJCAAAAA==.Yormaum:BAAALgADCgYJBgAAAA==.Yosha:BAAALgADCgcJEAAAAA==.',
Za='Zaartyn:BAAALgAFFAEJAQAAAA==.Zalupalkys:BAAALgAECgQJAwAAAA==.Zarexion:BAAALgADCggJDAAAAA==.',
Ze='Zeebeth:BAABLgAECn8fAAIIAAkJ2hSsLgALAgAIAAkJ2hSsLgALAgAAAA==.Zefi:BAABLgAECn8cAAIiAAkJkg8QGQB9AQAiAAkJkg8QGQB9AQAAAA==.Zenko:BAAALgADCgQJBAAAAA==.Zerokai:BAAALgAFFAMJAwAAAA==.',
Zh='Zhahira:BAAALgAECgUJDQAAAA==.',
Zi='Zipsy:BAACLgAFFH8GAAILAAMJXQWyhAClAAALAAMJXQWyhAClAAAuAAQKfzAAAgsACQlUD09UAMcBAAsACQlUD09UAMcBAAAA.',
Zo='Zomlo:BAAALgAECgEJAQAAAA==.Zonka:BAAALgAECgEJAQABLgAECgkJKgAbAIkJAA==.',
Zu='Zumtobel:BAAALgAECgQJBwAAAA==.Zuuko:BAACLgAFFH8ZAAIWAAQJ4CLKBwB+AQAWAAQJ4CLKBwB+AQAuAAQKfyYAAhYACQkeJh0EAAkDABYACQkeJh0EAAkDAAAA.',
Zy='Zyreth:BAAALgAECgYJCQAAAA==.',
['Ár']='Árthur:BAAALgAECgUJBwAAAA==.',
['Âr']='Ârtemis:BAAALgAECgUJBQABLgAFFAUJCwAJAKMJAA==.',
['År']='Åres:BAAALgAECgMJBgAAAA==.',
['Îs']='Îsadora:BAAALgADCgYJCQAAAA==.',
['Ýe']='Ýe:BAAALgADCgYJBgAAAA==.',
['ßu']='ßuzzibee:BAAALgAECgUJDAABLgAFFAIJCAASAOoOAA==.',
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
