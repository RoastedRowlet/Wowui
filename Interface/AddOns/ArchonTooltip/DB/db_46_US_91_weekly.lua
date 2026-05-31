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

local lookup = {'Paladin-Retribution','Druid-Balance','Shaman-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','Druid-Restoration','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','Warlock-Demonology','Warrior-Protection','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Druid-Feral','Unknown-Unknown','Shaman-Elemental','DemonHunter-Havoc','Rogue-Assassination','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection','Mage-Frost','DemonHunter-Devourer','Warlock-Affliction','Warlock-Destruction','Rogue-Subtlety','Evoker-Devastation','Druid-Guardian','Paladin-Holy',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=46,date='2026-05-30',data={Ad='Adolyn:BAAALgADCgkJCQAAAA==.Adventis:BAAALgADCgQJAwAAAA==.',
Al='Allavus:BAAALgADCgQJBQABLgAFFAUJEgABAL4cAA==.',
Am='Amrin:BAAALgAECgkJBgAAAA==.',
An='Andderson:BAAALgAECgEJAgAAAA==.Andersen:BAABLgAECn8jAAIBAAgJEB8rKABJAgABAAgJEB8rKABJAgAAAA==.Ando:BAAALgAECgEJAQABLgAECgkJLQACAG8ZAA==.Andryu:BAACLgAFFH8IAAICAAMJkgiELgCeAAACAAMJkgiELgCeAAAuAAQKfzwAAgIACQlHGpoKAJUCAAIACQlHGpoKAJUCAAAA.Anebel:BAAALgADCgkJCQAAAA==.Angelmuerte:BAAALgADCgkJDgAAAA==.Angyal:BAAALgAECgYJBwAAAA==.',
Ap='Apolion:BAAALgADCgYJBgAAAA==.',
Aq='Aquastar:BAAALgAECgEJAQAAAA==.',
Ar='Archerius:BAAALgADCgcJCwAAAA==.Ardre:BAAALgADCgEJAQAAAA==.Arkanis:BAABLgAECn8zAAIDAAgJlR/yGgBZAgADAAgJlR/yGgBZAgAAAA==.Arïel:BAABLgAECn8pAAQEAAgJYxuWDQB2AgAEAAgJXhuWDQB2AgAFAAEJfRuMXwBGAAAGAAEJMAVDigAPAAAAAA==.',
Az='Azalya:BAAALgAECgQJBAAAAA==.',
Ba='Backstabath:BAAALgAECgkJDgABLgAECgkJFwAHAM4hAA==.Banidor:BAAALgAECgIJAgAAAA==.',
Be='Becka:BAAALgADCgEJAQAAAA==.',
Bh='Bhrown:BAAALgAECgIJAgAAAA==.',
Bl='Bloodlyn:BAAALgADCgUJBQAAAA==.Blueming:BAAALgAECgMJBQAAAA==.',
Bo='Bonsai:BAABLgAECn8WAAMIAAYJFAiFPQC0AAAJAAYJAwYDXADIAAAIAAYJnwaFPQC0AAAAAA==.',
Br='Broadfang:BAACLgAFFH8lAAMKAAgJQB8FAwBtAQAKAAUJ9yIFAwBtAQALAAcJrBNZDwA4AQAuAAQKfyQABAoACQlPJZ0cAFoCAAsABwliIpAYAGcCAAoABgnHJJ0cAFoCAAwABAlWDjciAMMAAAAA.Broconis:BAAALgAECgUJBwAAAA==.',
Bu='Bubbleoseven:BAAALgAECgUJEAAAAA==.Bullorly:BAACLgAFFH8iAAINAAYJISG7GADSAQANAAYJISG7GADSAQAuAAQKfyEAAg0ACQnqJOQHACYDAA0ACQnqJOQHACYDAAAA.Bullwînkle:BAAALgADCgcJBwABLgAECgcJFQAOAIMFAA==.Bungulators:BAEALgAECgEJAQABLgAECgkJRQAPAMMXAA==.',
Ca='Capriestsunn:BAAALgAECgUJDQAAAA==.Casey:BAAALgAECgEJAQAAAA==.Catirus:BAAALgAECgEJAQAAAA==.',
Ch='Chunt:BAAALgAECgEJAQAAAA==.',
Cl='Clickshot:BAACLgAFFH8KAAIKAAMJmyCtPgAQAQAKAAMJmyCtPgAQAQAuAAQKf0cAAwoACQk/JnkBAHYDAAoACQk/JnkBAHYDAAsABAkEEv1ZANwAAAAA.Clipe:BAAALgAECgYJBgAAAA==.Clipee:BAAALgAECgkJEAAAAA==.Clipeskeg:BAABLgAECn8jAAMQAAkJQhwCDQBTAgAQAAkJQhwCDQBTAgARAAEJFwulhAA6AAAAAA==.Clipex:BAAALgAECgkJDgAAAA==.',
Co='Connor:BAAALgAECgEJAQAAAA==.Contagium:BAAALgAECgQJCgAAAA==.',
Cr='Crunchberry:BAAALgAFFAIJAgAAAA==.Cryptus:BAAALgADCgMJAQABLgAECgcJFQASAOwfAA==.',
Cy='Cynîc:BAAALgAECgYJCAAAAA==.',
['Cø']='Cønståntine:BAAALgAECgEJAQAAAA==.',
Da='Daddynature:BAAALgAECgUJDQAAAA==.Daddyÿ:BAAALgAECgYJBgAAAA==.Darenas:BAABLgAECn8oAAMGAAkJlxgEFwAuAgAGAAkJlxgEFwAuAgAEAAEJpA3qbQAvAAAAAA==.Darkspyro:BAAALgADCgEJAQAAAA==.Dasu:BAABLgAECn8uAAQHAAkJfQvGSQBUAQAHAAkJfQvGSQBUAQACAAYJNAjwRQDXAAATAAMJUQKiLgBSAAAAAA==.David:BAAALgADCgcJDwABLgAECgcJAQAUAAAAAA==.',
De='Deathbooze:BAACLgAFFH8OAAINAAUJ9yBFLgB8AQANAAUJ9yBFLgB8AQAuAAQKfysAAg0ACAnMIFAmAFYCAA0ACAnMIFAmAFYCAAAA.Deathmikee:BAACLgAFFH8FAAINAAMJHg+XhgDYAAANAAMJHg+XhgDYAAAuAAQKfzkAAg0ACQkaIbwJABIDAA0ACQkaIbwJABIDAAAA.Demonrush:BAAALgAECgEJAQABLgAFFAEJAQAUAAAAAA==.Deyst:BAAALgADCgkJCQABLgAECgEJAQAUAAAAAA==.',
Di='Dimethaline:BAAALgADCgcJBwAAAA==.Dinlek:BAAALgAECgkJDwAAAA==.Dinosoars:BAAALgADCgEJAQAAAA==.',
Dk='Dkmountain:BAABLgAECn8fAAIGAAcJGyFPEwBaAgAGAAcJGyFPEwBaAgAAAA==.',
Dr='Draknol:BAABLgAECn8YAAIMAAgJswQlKgBAAQAMAAgJswQlKgBAAQAAAA==.Drakos:BAAALgAECgQJAwAAAA==.Drunknfist:BAAALgAECgYJBwAAAA==.',
Du='Durton:BAACLgAFFH8JAAIJAAMJlhleJgD6AAAJAAMJlhleJgD6AAAuAAQKfycAAgkACQlBHTkYAIoCAAkACQlBHTkYAIoCAAAA.',
Ec='Echidna:BAABLgAFFH8GAAIKAAMJ+xUyTwDiAAAKAAMJ+xUyTwDiAAABLgAFFAUJDAAQAJsUAA==.Echø:BAAALgADCgUJBQAAAA==.',
Ed='Edison:BAACLgAFFH8KAAIJAAMJ1SR1FwA+AQAJAAMJ1SR1FwA+AQAuAAQKfzQAAwkACQkGISQMAJICAAkACQkGISQMAJICAAgAAwmAG3c+ALAAAAAA.Edrency:BAAALgADCgYJBgAAAA==.',
Ef='Eferis:BAAALgAECgkJDwAAAA==.',
El='Elder:BAAALgAECgYJBgAAAA==.Elderdorje:BAACLgAFFH8IAAISAAMJtxSRLADAAAASAAMJtxSRLADAAAAuAAQKfy8AAxIACQkjHesQAHoCABIACQkjHesQAHoCABEAAQnuAf6JACQAAAAA.Elesa:BAAALgADCgEJAQAAAA==.Elixe:BAAALgADCgEJAQAAAA==.Elondre:BAABLgAECn9EAAMDAAkJRCZxAADXAwADAAkJRCZxAADXAwAVAAEJ/wbIkgAyAAAAAA==.',
Em='Emomorf:BAABLgAECn8YAAIWAAcJRxAuKAAVAQAWAAcJRxAuKAAVAQAAAA==.Employee:BAACLgAFFH8eAAIJAAcJtx0JBQDcAQAJAAcJtx0JBQDcAQAuAAQKfyIAAwkACQmvJVYBALsDAAkACQmvJVYBALsDAA8AAwmCGvoxALUAAAAA.',
Ev='Evangeliné:BAAALgAECgYJEwABLgAECgkJRQAFAHkZAA==.',
Ex='Exavier:BAAALgADCgQJBAAAAA==.',
Fe='Femboi:BAAALgAECgkJDAAAAA==.',
Fi='Fistsofseno:BAAALgAECgkJCgAAAA==.Fizzenator:BAACLgAFFH8FAAIMAAMJihx7FgAFAQAMAAMJihx7FgAFAQAuAAQKfygAAgwACQlfHMYIAIUCAAwACQlfHMYIAIUCAAAA.',
Fr='Freshlight:BAAALgAECgYJBgABLgAECgkJNgASAJIhAA==.',
Fw='Fweeb:BAAALgAECgMJAwAAAA==.',
Ga='Galatea:BAACLgAFFH8SAAIBAAUJvhzAJQBPAQABAAUJvhzAJQBPAQAuAAQKfyoAAgEACQmbInsKAP8CAAEACQmbInsKAP8CAAAA.Galifen:BAACLgAFFH8IAAICAAMJ/yMXFgA8AQACAAMJ/yMXFgA8AQAuAAQKf0cAAgIACQl9JkIAAJQDAAIACQl9JkIAAJQDAAAA.Gank:BAABLgAFFH8FAAIXAAMJDhcNBgD4AAAXAAMJDhcNBgD4AAAAAA==.Gargyll:BAAALgADCgUJBQAAAA==.Garysparks:BAAALgAECgEJAgAAAA==.',
Ge='Gelidon:BAABLgAECn8wAAMYAAkJshmOCQA8AgAYAAkJshmOCQA8AgAZAAcJTwz0OAAoAQAAAA==.Getoutalive:BAAALgADCgEJAQAAAA==.',
Gh='Ghreen:BAABLgAECn8UAAIRAAkJFRshDABuAgARAAkJFRshDABuAgAAAA==.',
Gi='Gilgahmesh:BAABLgAECn8qAAMaAAgJdwysGQAyAQAaAAgJdwysGQAyAQABAAEJaQN3WAEmAAABLgAECgkJMQANAFIJAA==.',
Gn='Gnomegrown:BAABLgAECn8rAAICAAgJLxfwGQDjAQACAAgJLxfwGQDjAQAAAA==.',
Gr='Gragehorn:BAAALgAECgEJAQAAAA==.Grapejuice:BAAALgAECgEJAQAAAA==.Gruvi:BAAALgAECgEJAQAAAA==.',
Gu='Gumbusta:BAAALgAECgcJDwAAAA==.Gummiie:BAAALgADCgEJAQAAAA==.Gunrunner:BAAALgADCgcJBwAAAA==.',
Ha='Halestorm:BAAALgADCgYJBgAAAA==.Halyer:BAABLgAECn8WAAMYAAgJ7w7QFgBPAQAYAAYJLhDQFgBPAQAZAAUJZQRPaQBzAAAAAA==.Hamalainen:BAAALgAECgEJAgABLgAECgkJNgASAJIhAA==.Hankthesnake:BAAALgADCgcJGwABLgAECgEJAQAUAAAAAA==.',
He='Helioboops:BAAALgAECgQJBAAAAA==.Hexdaman:BAAALgAECgMJBQAAAA==.',
Hi='Highcurious:BAAALgADCggJCAABLgAECgkJNgASAJIhAA==.',
Ho='Hobbz:BAACLgAFFH8dAAIBAAYJDB7HAwC2AQABAAYJDB7HAwC2AQAuAAQKfy8AAgEACQm2JB0HAF8DAAEACQm2JB0HAF8DAAAA.Hodge:BAAALgADCgMJAwAAAA==.Hoid:BAAALgADCgkJCgAAAA==.',
Il='Illandros:BAABLgAECn8jAAIGAAgJdBILIgCXAQAGAAgJdBILIgCXAQAAAA==.Illidankmeme:BAAALgADCgIJAgAAAA==.',
In='Ingredient:BAABLgAECn8nAAITAAkJMBO5CgDwAQATAAkJMBO5CgDwAQAAAA==.Inspire:BAABLgAECn8VAAIHAAgJ9xwwIwAvAgAHAAgJ9xwwIwAvAgAAAA==.',
Is='Isinia:BAABLgAECn8VAAIOAAcJgwWkoADzAAAOAAcJgwWkoADzAAAAAA==.',
Ja='Janitor:BAAALgADCgMJAgAAAA==.Jayas:BAABLgAECn8VAAISAAcJ7B+vEAB8AgASAAcJ7B+vEAB8AgAAAA==.Jayim:BAABLgAFFH8GAAIHAAMJvAHpSQB+AAAHAAMJvAHpSQB+AAAAAA==.Jaína:BAABLgAECn8aAAIbAAgJ/gteewBmAQAbAAgJ/gteewBmAQABLgAECggJJwABAAccAA==.',
Jc='Jcvd:BAAALgADCgQJBAABLgAECgkJNgASAJIhAA==.',
Je='Jencks:BAAALgAECgUJCQABLgAECgkJLQACAG8ZAA==.',
Ji='Jiren:BAABLgAECn82AAMSAAkJkiHCBQAwAwASAAkJkiHCBQAwAwARAAMJTgktXwCTAAAAAA==.',
Jo='Johnson:BAABLgAECn8eAAIPAAgJ+hrbCwAZAgAPAAgJ+hrbCwAZAgAAAA==.Johnsunwell:BAAALgADCgQJAwAAAA==.Joran:BAABLgAECn8nAAIBAAgJZxO/UwC2AQABAAgJZxO/UwC2AQAAAA==.',
Ju='Juckbolas:BAAALgAECgQJBAAAAA==.Juicyjj:BAABLgAECn8ZAAINAAgJCw0fhABGAQANAAgJCw0fhABGAQAAAA==.Jukesnaxx:BAAALgAECgMJBQAAAA==.',
['Jë']='Jësûs:BAAALgAECgEJAQAAAA==.',
Ka='Kaije:BAAALgADCgMJAwAAAA==.',
Ke='Kelekii:BAAALgADCgIJAgAAAA==.',
Kr='Kravoxx:BAAALgADCgUJCQABLgAECgIJAgAUAAAAAA==.Kro:BAABLgAECn8fAAIBAAgJ3BFtbQB5AQABAAgJ3BFtbQB5AQAAAA==.Krysess:BAAALgADCgEJAQAAAA==.Krèios:BAAALgAECgYJBgABLgAFFAQJDwAcAB8OAA==.',
Le='Leanea:BAAALgAECgMJAwAAAA==.Lenayuh:BAAALgAECgQJAwAAAA==.',
Li='Lich:BAAALgAFFAQJAgAAAA==.Liera:BAABLgAECn8rAAINAAgJRBk8NAAaAgANAAgJRBk8NAAaAgAAAA==.',
Ll='Lloydlei:BAABLgAECn8yAAQOAAkJBh1nGgB4AgAOAAkJdxxnGgB4AgAdAAQJ5hXJEgAbAQAeAAMJEhd6IgCCAAAAAA==.',
Lo='Lodin:BAAALgAECgcJBwABLgAFFAQJDQAfANQHAA==.',
Lu='Luminå:BAABLgAECn8gAAIeAAkJZhg6CgCCAQAeAAkJZhg6CgCCAQAAAA==.',
Ly='Lylenn:BAAALgADCgkJGwAAAA==.',
Ma='Madora:BAAALgADCgQJBAAAAA==.Maibisan:BAABLgAECn9HAAMWAAkJLSaHAAB/AwAWAAkJLSaHAAB/AwAcAAkJpCTeAwA6AwAAAA==.Malificent:BAABLgAECn8dAAIOAAcJ7R2MOADrAQAOAAcJ7R2MOADrAQAAAA==.Malighn:BAABLgAECn8xAAINAAkJUgn6XgCYAQANAAkJUgn6XgCYAQAAAA==.Masseffex:BAAALgAECgcJEQAAAA==.',
Mc='Mcshooty:BAAALgAECgYJDAAAAA==.',
Mo='Modi:BAAALgAECgEJAQAAAA==.Mookong:BAAALgADCgEJAQAAAA==.Moonsliver:BAAALgAECgEJBAAAAA==.Mordecâi:BAAALgAECgEJAQAAAA==.Morf:BAAALgAECgMJAwABLgAECgkJMAAYALIZAA==.Morganä:BAAALgAECgQJDQAAAA==.Morthrin:BAABLgAECn8VAAIHAAkJ5hQSJAAXAgAHAAkJ5hQSJAAXAgAAAA==.',
Mu='Muhrieyuh:BAAALgADCgQJBAAAAA==.',
My='Mysticdibs:BAAALgAECgEJAQAAAA==.Mystwolf:BAABLgAECn8wAAIDAAgJzB6TFABwAgADAAgJzB6TFABwAgAAAA==.',
Ne='Ned:BAAALgAECgIJAgABLgAECgcJDgAUAAAAAA==.Negora:BAAALgAECgEJAQAAAA==.Nelaris:BAAALgADCgEJAQAAAA==.',
Ni='Niccelndime:BAABLgAECn8VAAIMAAYJ5BuIHwCRAQAMAAYJ5BuIHwCRAQAAAA==.Nightember:BAABLgAECn8aAAQZAAkJjQ+jHwDBAQAZAAkJjQ+jHwDBAQAYAAcJ+gfHGwAPAQAgAAEJgAmeJAAuAAABLgAFFAMJCAASALcUAA==.Nightski:BAABLgAECn8qAAIHAAkJgBd5HgA+AgAHAAkJgBd5HgA+AgAAAA==.Nikolatesla:BAAALgAECgcJDQAAAA==.Nizzari:BAACLgAFFH8NAAIfAAQJ1Ae3GwAeAQAfAAQJ1Ae3GwAeAQAuAAQKfzUAAx8ACQk1FZkTAO8BAB8ACQk1FZkTAO8BABcAAQmHCf0iADkAAAAA.',
No='Nomas:BAAALgAECgYJBgAAAA==.Nothalyer:BAABLgAECn8zAAIYAAkJyQ58EQCeAQAYAAkJyQ58EQCeAQAAAA==.',
Of='Offline:BAABLgAECn8XAAIHAAgJziEyCwD6AgAHAAgJziEyCwD6AgAAAA==.',
Oh='Ohms:BAACLgAFFH8IAAIbAAMJcgfcewDIAAAbAAMJcgfcewDIAAAuAAQKfzcAAhsACQmeGtMvAEICABsACQmeGtMvAEICAAAA.',
Ol='Olaria:BAAALgADCgYJGQAAAA==.',
Or='Orwasitme:BAAALgADCgEJAQABLgAECggJHwAJAJsTAA==.Orwasitshrek:BAABLgAECn8fAAIJAAgJmxOrJwCpAQAJAAgJmxOrJwCpAQAAAA==.Orwasitwrekt:BAAALgADCgkJCQABLgAECggJHwAJAJsTAA==.',
Pa='Palabop:BAAALgAECgYJEQAAAA==.Paladinii:BAAALgAECgQJBwAAAA==.',
Pl='Planec:BAAALgAECgYJBgAAAA==.',
Po='Polytots:BAACLgAFFH8OAAMDAAYJzALiKAAcAQADAAYJzALiKAAcAQAVAAUJ+ApVJADuAAAuAAQKfzIAAwMACQlREeA7AKIBAAMACAlSEuA7AKIBABUACQlUEyIsAHsBAAAA.',
Pr='Proteus:BAAALgADCgMJAwAAAA==.',
Qi='Qiller:BAAALgAECgcJDgAAAA==.',
Qu='Quinne:BAAALgADCgEJAQABLgAECgEJAQAUAAAAAA==.',
Ra='Ranin:BAAALgAECgcJDAAAAA==.Razius:BAAALgAECgkJEgAAAA==.',
Ri='Ricklepick:BAAALgAECgYJEgABLgAECgkJNgASAJIhAA==.Riplordfire:BAAALgAECgEJAQAAAA==.',
Ro='Roadsign:BAAALgAECgYJEAAAAA==.Rottey:BAAALgAECgMJAwAAAA==.Roxette:BAAALgADCgcJBwAAAA==.',
Ry='Ryzenther:BAAALgAECgYJCQAAAA==.',
Sa='Salvation:BAAALgAECgkJEgAAAA==.Sanctis:BAAALgAECgYJCQAAAA==.Santan:BAAALgADCgIJAgAAAA==.Satrat:BAAALgAECgEJAQAAAA==.',
Sc='Scarecrow:BAAALgAECgEJAgAAAA==.',
Se='Sealgair:BAAALgAECgEJBgAAAA==.Senovourer:BAABLgAECn8fAAIcAAkJjCEJCwAqAwAcAAkJjCEJCwAqAwAAAA==.',
Sh='Shabamoo:BAABLgAECn85AAMHAAkJsyAWBQBaAwAHAAkJsyAWBQBaAwATAAEJggevRgAuAAAAAA==.Shakkes:BAAALgAECgEJAQAAAA==.Shasato:BAACLgAFFH8FAAIhAAIJux0LFgCvAAAhAAIJux0LFgCvAAAuAAQKfzgAAiEACAlOIUAFAJwCACEACAlOIUAFAJwCAAAA.Shelian:BAAALgAECgEJAQAAAA==.Shiranai:BAAALgAECgEJAQAAAA==.Shoosty:BAAALgADCgcJDAAAAA==.',
Si='Sicarii:BAAALgADCgcJCAAAAA==.Sindora:BAAALgADCgYJBgAAAA==.Sizouze:BAABLgAECn8jAAIFAAgJvQa3NgANAQAFAAgJvQa3NgANAQAAAA==.',
Sk='Skeeter:BAAALgAECgYJBgAAAA==.Sklonda:BAAALgADCgYJBgAAAA==.Skyepic:BAACLgAFFH8bAAIiAAgJKRnGAQDuAQAiAAgJKRnGAQDuAQAuAAQKfycAAyIACQmjIi0HAPkCACIACQmjIi0HAPkCAAEABAllEn7VAOAAAAAA.Skylight:BAAALgAECgEJAQAAAA==.',
Sn='Snugwalnut:BAACLgAFFH8dAAIDAAYJ2yDkBQAuAgADAAYJ2yDkBQAuAgAuAAQKfzcAAgMACAlHI78LAOcCAAMACAlHI78LAOcCAAAA.',
So='Soejoedi:BAABLgAECn8tAAICAAkJbxlUDwBSAgACAAkJbxlUDwBSAgAAAA==.',
Sp='Spicyburrito:BAAALgAECgcJBwAAAA==.',
St='Stitchzpls:BAAALgAECgUJCQAAAA==.',
Su='Sunhammer:BAAALgAECgEJAQAAAA==.Sunsworn:BAAALgAECgQJBwAAAA==.',
Sw='Sweetyboi:BAAALgAECgYJDwAAAA==.',
Sy='Sythar:BAAALgAECgEJAQAAAA==.',
Ta='Taintedrush:BAAALgAFFAEJAQAAAA==.Talan:BAAALgAECgMJAwABLgAECgcJFQASAOwfAA==.Tarhostamir:BAABLgAECn8aAAICAAcJxw9dMQA8AQACAAcJxw9dMQA8AQAAAA==.Taurup:BAAALgAECgcJDwABLgAFFAQJDQAfANQHAA==.Tazz:BAABLgAECn8cAAIKAAcJqgbQiQASAQAKAAcJqgbQiQASAQAAAA==.',
Te='Tecnine:BAAALgADCgUJBQAAAA==.Teledar:BAAALgAECgQJCAAAAA==.',
Th='Thaluus:BAAALgADCgYJCgAAAA==.Thaysinga:BAAALgAFFAIJAgAAAA==.Thelandlord:BAACLgAFFH8UAAIYAAYJahVpBQChAQAYAAYJahVpBQChAQAuAAQKfxwAAxgACAkOG9oMAGgCABgACAkOG9oMAGgCACAAAwnJDqIvAJoAAAAA.Theshape:BAAALgADCgMJAwAAAA==.Thunderblast:BAABLgAECn8fAAIJAAcJBCNoEwBEAgAJAAcJBCNoEwBEAgAAAA==.Thuss:BAABLgAECn8oAAIcAAkJgxqbGABtAgAcAAkJgxqbGABtAgAAAA==.',
Ti='Titgunniz:BAAALgADCgYJCQAAAA==.',
Tu='Tugnutz:BAAALgAECgUJDQAAAA==.Tuk:BAAALgAECgQJBAAAAA==.',
Tw='Twirlywhirly:BAAALgAECgcJDAAAAA==.',
['Tè']='Tèmpos:BAAALgAECgMJAwAAAA==.',
Ul='Ulansiola:BAAALgAECgEJAQAAAA==.',
Un='Unplug:BAAALgAECgUJDQAAAA==.',
Va='Vander:BAAALgAECgQJBAABLgAECgcJFQASAOwfAA==.Vanidossa:BAABLgAECn8cAAIGAAcJvwy2MwAoAQAGAAcJvwy2MwAoAQAAAA==.Varygud:BAAALgADCgUJBgAAAA==.Vayper:BAACLgAFFH8IAAIGAAMJLhMYHgDdAAAGAAMJLhMYHgDdAAAuAAQKf0gAAgYACQl5I3UCADADAAYACQl5I3UCADADAAAA.',
Ve='Veins:BAAALgAECgEJAQAAAA==.Verdict:BAACLgAFFH8IAAIiAAMJnBOzKgC7AAAiAAMJnBOzKgC7AAAuAAQKfxYAAiIACQkCF/EkAMoBACIACQkCF/EkAMoBAAAA.',
Vo='Voklin:BAAALgAECgQJBAAAAA==.',
We='Weemsy:BAABLgAECn81AAIJAAkJXiT1AwAYAwAJAAkJXiT1AwAYAwAAAA==.',
Wi='Wildfire:BAACLgAFFH8fAAIMAAYJJCQIAgD7AQAMAAYJJCQIAgD7AQAuAAQKfzQAAgwACQntJoUAAJEDAAwACQntJoUAAJEDAAAA.Wildfirë:BAAALgAECgYJBgABLgAFFAYJHwAMACQkAA==.Willthewise:BAAALgADCgIJAgAAAA==.',
Wo='Wolffei:BAAALgAECgEJAQAAAA==.Wolfhammer:BAABLgAECn8uAAIPAAkJWiByBADLAgAPAAkJWiByBADLAgAAAA==.Wolflee:BAAALgAECgYJDwAAAA==.Wolfmend:BAABLgAECn8WAAMHAAYJhhtvPgCGAQAHAAYJhhtvPgCGAQACAAEJ1gK7lQAaAAAAAA==.',
Xa='Xamid:BAAALgAECgYJEAAAAA==.Xaxfen:BAACLgAFFH8TAAIPAAcJgBbxBAAoAQAPAAcJgBbxBAAoAQAuAAQKfyQABA8ACAlzItcJAHoCAA8ACAlzItcJAHoCAAkABQlEFNxMAPwAAAgAAQkAAAh8AAAAAAAA.',
['Xê']='Xêndâr:BAAALgADCgQJBAAAAA==.',
Yo='Yogurt:BAAALgAECgIJAgAAAA==.',
Za='Zappieboy:BAAALgAECgcJDQAAAA==.',
Ze='Zeuree:BAAALgAECgEJAQAAAA==.Zeurie:BAABLgAFFH8HAAIEAAMJqQj1KwC7AAAEAAMJqQj1KwC7AAAAAA==.',
Zu='Zulgrimm:BAAALgADCgMJAwAAAA==.',
Zy='Zyfèr:BAAALgAECgcJEwAAAA==.',
['Zî']='Zîmìk:BAAALgAECgQJBgAAAA==.',
['Às']='Àsh:BAACLgAFFH8FAAIFAAMJyhzDFAD5AAAFAAMJyhzDFAD5AAAuAAQKfzoAAgUACQnqIqUCAGYDAAUACQnqIqUCAGYDAAAA.',
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
