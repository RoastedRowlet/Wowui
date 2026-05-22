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

local lookup = {'Warrior-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Blood','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Monk-Mistweaver','Mage-Frost','Priest-Shadow','DeathKnight-Unholy','Rogue-Assassination','Rogue-Subtlety','Hunter-BeastMastery','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Druid-Restoration','Druid-Balance','Priest-Holy','Mage-Arcane','Priest-Discipline','Paladin-Protection','Monk-Brewmaster','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Warrior-Arms','Hunter-Marksmanship','Monk-Windwalker','Shaman-Enhancement','Shaman-Elemental','Druid-Feral','Druid-Guardian','DeathKnight-Frost','Hunter-Survival','Mage-Fire',}
local provider = {region='US',realm='Ghostlands',name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Ado:BAAALgAECgEJAQAAAA==.',
Ae='Aelestus:BAABLgAECn8tAAIBAAkJhyLQAQAOAwABAAkJhyLQAQAOAwAAAA==.Aelèna:BAACLgAFFH8JAAICAAMJVhsrBADcAAACAAMJVhsrBADcAAAuAAQKfycABAIACAnmIYsDAFMCAAIACAmqIIsDAFMCAAMAAwkSDXBUAJcAAAQAAgm5IR6zAGEAAAAA.Aerion:BAAALgAECgEJAQAAAA==.Aethylthryth:BAAALgADCgMJAwAAAA==.',
Af='Aft:BAACLgAFFH8YAAIFAAUJcRykCwA9AQAFAAUJcRykCwA9AQAuAAQKfx8AAgUACQnXHS8MAE4CAAUACQnXHS8MAE4CAAAA.Aftdruid:BAAALgAECgYJDQABLgAFFAUJGAAFAHEcAA==.',
Ag='Agonize:BAAALgADCgUJCAAAAA==.Agörab:BAAALgAECgIJBAAAAA==.',
Ai='Airdeezy:BAABLgAFFH8GAAIGAAQJJQwwDABBAQAGAAQJJQwwDABBAQAAAA==.Aislin:BAAALgAECgcJDQAAAQ==.',
Ak='Akkord:BAAALgAECgYJBwAAAA==.Akumu:BAABLgAECn8sAAQHAAgJhBnaDQDoAQAHAAcJSRraDQDoAQAIAAgJmBPiVwBWAQAJAAQJHhYVDgAJAQAAAA==.',
Al='Alarkin:BAAALgAECgUJBQABLgAFFAYJFQAKAAQLAA==.Alcarde:BAABLgAECn8yAAILAAkJtRD7QADXAQALAAkJtRD7QADXAQAAAA==.Aldoan:BAAALgAECgMJBAAAAA==.Alfurian:BAAALgADCgYJBgAAAA==.Alialeman:BAAALgAECgQJBAAAAA==.Alistiri:BAABLgAECn8qAAIMAAkJuyEOBQDQAgAMAAkJuyEOBQDQAgAAAA==.Alistraza:BAACLgAFFH8dAAINAAUJLR5vIAB1AQANAAUJLR5vIAB1AQAuAAQKfzIAAg0ACAkAI/sWAPICAA0ACAkAI/sWAPICAAAA.Alix:BAABLgAECn8sAAMOAAgJyiNeAQDBAgAOAAgJyiNeAQDBAgAPAAIJ/B4WUQCiAAAAAA==.Allforge:BAABLgAECn8lAAIGAAgJ0BouGADfAQAGAAgJ0BouGADfAQAAAA==.Almina:BAABLgAECn8YAAIQAAkJnAl8OwCcAQAQAAkJnAl8OwCcAQAAAA==.Alpal:BAACLgAFFH8bAAIRAAYJjCXGAQBtAgARAAYJiyXGAQBtAgAuAAQKf0EAAxEACQn+JJAAALEDABEACQn+JJAAALEDABIABwnCFaJXAHsBAAAA.Alphabetrium:BAAALgADCgQJBAABLgAECgcJDgATAAAAAA==.Alyreu:BAAALgAECgcJDAAAAA==.',
An='Anavi:BAAALgADCgcJDgAAAA==.Andalya:BAABLgAECn8kAAMUAAgJ9wL5cACfAAAUAAgJ9wL5cACfAAAVAAIJSwHDdgAgAAAAAA==.Andarial:BAAALgAECggJDAAAAA==.Ando:BAAALgADCgYJBgABLgAECgEJAQATAAAAAA==.Angelenaholy:BAABLgAECn8fAAIWAAkJNBSYEgD+AQAWAAkJNBSYEgD+AQAAAA==.Animantarx:BAAALgADCgcJCgAAAA==.',
Ao='Aos:BAAALgADCgcJBwAAAA==.',
Ap='Aprix:BAAALgAECgUJBwAAAA==.',
Ar='Aralyn:BAAALgADCgMJAwAAAA==.Arejay:BAAALgAECgYJEgAAAA==.Arellia:BAAALgADCgUJBQAAAA==.Arshika:BAABLgAECn8pAAILAAcJqB2aPQDiAQALAAcJqB2aPQDiAQAAAA==.Arthonix:BAABLgAECn8cAAINAAgJ0R9XLAAHAgANAAgJ0R9XLAAHAgAAAA==.Arthurleywin:BAABLgAECn8mAAMLAAgJexKcWQCPAQALAAgJexKcWQCPAQAXAAEJzQG8IQAlAAAAAA==.Arvis:BAAALgADCgYJBgAAAA==.',
As='Asagiri:BAAALgADCgIJAgAAAA==.Ascadian:BAAALgAECgYJAwAAAA==.Ashaki:BAABLgAECn8kAAIYAAgJ1w7yGACxAQAYAAgJ1w7yGACxAQAAAA==.Asmodéus:BAAALgAECgUJAgAAAA==.',
At='Athena:BAEALgADCgMJAwAAAQ==.Atla:BAABLgAECn8UAAIUAAYJdBsqKwC2AQAUAAYJdBsqKwC2AQAAAA==.Atretes:BAAALgAECgMJAwAAAA==.',
Au='Audi:BAABLgAECn8hAAIEAAgJmhfzLQDGAQAEAAgJmhfzLQDGAQAAAA==.Auntiy:BAAALgAECgEJAQABLgAECggJLQAZALYfAA==.Auroramoon:BAABLgAECn8dAAIaAAcJfRFFKQAsAQAaAAcJfRFFKQAsAQAAAA==.Autobots:BAAALgADCgQJBAAAAA==.',
Ax='Axionar:BAABLgAECn8tAAQbAAkJChmHDwAmAgAbAAkJChmHDwAmAgAcAAYJBBfxHACdAQAdAAMJ9w7QNABuAAAAAA==.',
Az='Azeroth:BAAALgAECgMJAwAAAA==.Azhag:BAAALgAECgcJDQABLgADCgIJFAATAAAAAA==.Azmadi:BAAALgADCgcJAgAAAA==.Azshauria:BAAALgADCgEJAQAAAA==.Azurend:BAABLgAECn8xAAMdAAgJ/xtvAwAgAgAdAAgJ7BtvAwAgAgAbAAcJVhZDIQB+AQAAAA==.',
Ba='Babunii:BAAALgADCggJFAAAAA==.Baeblades:BAAALgADCgYJBgABLgAFFAYJFQAKAAQLAA==.Bahula:BAABLgAECn8zAAIeAAgJIA/HNACAAQAeAAgJIA/HNACAAQAAAA==.Bainehuln:BAABLgAECn8dAAIQAAkJERUAIgANAgAQAAkJERUAIgANAgAAAA==.Bainezhull:BAAALgAECgMJBAAAAA==.Banee:BAAALgAECgUJBQAAAA==.Bastianos:BAABLgAECn8oAAMRAAkJbRskJwDxAQARAAgJAxokJwDxAQASAAYJfBdzcgA9AQAAAA==.Batsom:BAABLgAECn8fAAMLAAgJcBxJPwDdAQALAAgJMxlJPwDdAQAXAAUJRR5/DgDbAAAAAA==.Batsop:BAAALgADCgMJAwAAAA==.Battlekattel:BAAALgADCgIJAgAAAA==.Bayn:BAAALgAECgEJAgAAAA==.',
Be='Bearbuttkick:BAAALgADCgcJEQABLgAFFAUJEgAPABEVAA==.Beekeeper:BAAALgAECgEJAQAAAA==.Bellapearl:BAABLgAECn8UAAIWAAYJtQodMQD+AAAWAAYJtQodMQD+AAAAAA==.Belvis:BAAALgAFFAEJAQAAAA==.Benthus:BAAALgADCgYJBgAAAA==.Benzoth:BAAALgADCgYJCgAAAA==.Bergin:BAABLgAECn8gAAMWAAgJRx8rCQCNAgAWAAgJRx8rCQCNAgAYAAIJcwyiSgBaAAAAAA==.Bernes:BAAALgADCgUJBQAAAA==.Besticando:BAAALgADCgUJCAAAAA==.',
Bi='Biffle:BAAALgAECgkJCgAAAA==.Biggjãx:BAAALgADCgEJAQAAAA==.Bigowltittiz:BAAALgAECgIJAwAAAA==.Bigteef:BAAALgADCggJCQAAAA==.Bigtimestuff:BAAALgADCgEJAQAAAA==.Bigzaddy:BAAALgADCgYJBgAAAA==.Biozone:BAAALgADCgYJBgAAAA==.Birdhouse:BAABLgAECn8aAAIMAAgJBCA5CgBiAgAMAAgJBCA5CgBiAgAAAA==.',
Bl='Blackthornn:BAACLgAFFH8bAAMOAAYJ6RrrAAC5AQAOAAYJyBfrAAC5AQAPAAUJDxvwCgBkAQAuAAQKf0EAAw4ACQm4I+oAAPkCAA4ACQkyI+oAAPkCAA8ACAlrI8UFAJECAAAA.Blade:BAAALgADCgcJCAAAAA==.Blkmagic:BAAALgAECgcJEwAAAA==.Bloodcircus:BAABLgAECn8aAAMGAAgJziM3BQBUAwAGAAgJziM3BQBUAwAfAAEJxwd0PABAAAAAAA==.Bloodreign:BAABLgAECn8dAAICAAcJORvxBgDFAQACAAcJORvxBgDFAQAAAA==.Blotto:BAAALgAECgYJCgAAAA==.Blottzilla:BAACLgAFFH8bAAIcAAYJXBjdBQDwAQAcAAYJXBjdBQDwAQAuAAQKf0EAAxwACQk1IRcBAHcDABwACQk1IRcBAHcDABsABgl4IaUWANYBAAAA.',
Bo='Bobbyray:BAAALgAECgYJBgAAAA==.Bobertbigg:BAACLgAFFH8HAAIRAAMJ+SMHFAA4AQARAAMJ+SMHFAA4AQAuAAQKfxYAAhEACQkhGGUjAAYCABEACQkhGGUjAAYCAAAA.Bobó:BAAALgADCgYJCAAAAA==.Bowbuttkick:BAAALgAECgEJAQABLgAFFAUJEgAPABEVAA==.Bowfle:BAAALgAECgYJEQAAAA==.Boxiebounce:BAAALgADCgQJBAAAAA==.Boxiebrown:BAACLgAFFH8GAAIQAAMJLhdCQwCxAAAQAAMJLhdCQwCxAAAuAAQKfx0AAxAACQnVFh0aAGsCABAACQnVFh0aAGsCACAAAQlFAfqaABYAAAAA.',
Br='Bralae:BAAALgADCgcJCAABLgAECggJHgALAGofAA==.Breaya:BAAALgAECgcJEwAAAA==.Brewskiez:BAAALgAECgYJBwAAAA==.Broachy:BAAALgAECgEJAQAAAA==.Brokuo:BAACLgAFFH8QAAMNAAcJoRf6CQDxAQANAAYJoRf6CQDxAQAFAAEJAABmLgAAAAAuAAQKfxYAAg0ACAmAGiBRAP4BAA0ACAmAGiBRAP4BAAAA.Brøwnies:BAAALgADCgUJBQAAAA==.Brüdilicious:BAAALgADCgEJAQAAAA==.',
Bu='Bustinyabutt:BAAALgADCgYJBgABLgAECggJIgAVAEkTAA==.Buzzlez:BAACLgAFFH8XAAIWAAYJ1hT/AgDbAQAWAAYJ1hT/AgDbAQAuAAQKfz4AAxYACQlHH1cEAAMDABYACQlHH1cEAAMDAAwAAQn+A6FoACcAAAAA.',
['Bé']='Béchamel:BAAALgAECgEJAQAAAA==.',
Ca='Cace:BAAALgADCgQJBAABLgAFFAUJEAAGAKIXAA==.Calboltz:BAAALgAECgQJBAAAAA==.Camspally:BAABLgAECn8ZAAISAAYJvAN+xgCtAAASAAYJvAN+xgCtAAAAAA==.Camthomp:BAECLgAFFH8GAAILAAMJjw8iVwD2AAALAAMJjw8iVwD2AAAuAAQKfyUAAgsACAlvH9ItAB8CAAsACAlvH9ItAB8CAAAA.Carbonara:BAAALgADCgUJBQAAAA==.Carnage:BAABLgAECn8ZAAMUAAYJXhc3PABbAQAUAAYJXhc3PABbAQAVAAIJeATJdgAgAAAAAA==.Carvo:BAAALgADCgQJBgAAAA==.Cassady:BAACLgAFFH8KAAINAAMJFCGbVAAHAQANAAMJFCGbVAAHAQAuAAQKfyYAAw0ACAnOIVUtAIMCAA0ACAnOIVUtAIMCAAUAAQl4FYNDADsAAAAA.Cat:BAABLgAECn8qAAIVAAgJcB+hCgBeAgAVAAgJcB+hCgBeAgAAAA==.Caìrin:BAAALgAECgUJCAABLgADCgIJFAATAAAAAA==.',
Ce='Celd:BAEBLgAECn8dAAMfAAkJiBydBgBEAgAfAAkJ2hudBgBEAgAGAAQJvBqbVQCdAAAAAA==.Celdina:BAAALgADCgEJAQAAAA==.Celdir:BAEALgADCgEJAQABLgAECgkJHQAfAIgcAA==.Celmac:BAAALgAECgEJAQAAAA==.',
Ch='Chaddrique:BAAALgAECgYJDgAAAA==.Chahae:BAAALgAECgUJBQAAAA==.Chanterelle:BAABLgAECn8rAAIUAAgJuiI2BwALAwAUAAgJuiI2BwALAwAAAA==.Cheerwine:BAAALgAECgQJCQAAAA==.Cheezits:BAACLgAFFH8JAAISAAMJSRgwNgAEAQASAAMJSRgwNgAEAQAuAAQKfyYAAxIACQlAIrUSAP0CABIACQlAIrUSAP0CABEABgnzEM4uAFEBAAAA.Chellevisty:BAAALgADCgYJBgAAAA==.Chiforce:BAABLgAECn8jAAIKAAYJqh4ZKAB0AQAKAAYJqh4ZKAB0AQAAAA==.Chronicle:BAAALgAECgQJCAAAAA==.Chrysus:BAAALgADCgcJDgAAAA==.',
Cl='Clinician:BAACLgAFFH8GAAIYAAMJhQOIIgC0AAAYAAMJhQOIIgC0AAAuAAQKfysABBYACAknGI8WACgCABYACAn7Fo8WACgCABgACAmxEg4SAP0BAAwAAQlXGQNaAEQAAAAA.Clowncar:BAAALgADCgkJCQAAAA==.',
Cn='Cndr:BAAALgAECgEJAQAAAA==.',
Co='Cowbunga:BAAALgAECgEJAQAAAA==.',
Cr='Crazzenburns:BAABLgAECn8jAAQhAAkJ1hVvFADFAQAhAAkJ1hVvFADFAQAKAAgJaRI2HQCyAQAaAAIJPQhMeQAsAAAAAA==.Creamer:BAABLgAECn8rAAQeAAkJ+g4AKwC1AQAeAAkJ+g4AKwC1AQAiAAIJAgifJwBiAAAjAAEJXAE3igAaAAAAAA==.Crunched:BAACLgAFFH8TAAMVAAUJMxDsCwArAQAVAAUJMxDsCwArAQAUAAIJ6gMrQwBuAAAuAAQKfzYAAxUACAk+H1wKAGQCABUACAk+H1wKAGQCABQAAwntCmmtAGsAAAAA.Crunches:BAAALgAFFAEJAQABLgAFFAUJEwAVADMQAA==.',
Cu='Cutedwarfxd:BAACLgAFFH8aAAIFAAcJciS+AAB3AgAFAAcJciS+AAB3AgAuAAQKfx8AAgUACQm4JSoCAFQDAAUACQm4JSoCAFQDAAAA.',
Cw='Cwds:BAAALgAECgUJCwAAAA==.',
['Cä']='Cärtä:BAAALgADCgMJAwAAAA==.',
['Cø']='Cøøkies:BAAALgADCgEJAQAAAA==.',
Da='Dabstar:BAAALgADCgYJBgAAAA==.Damane:BAAALgAECgYJCgAAAA==.Danìel:BAACLgAFFH8aAAIEAAYJ0Q+3FACCAQAEAAYJ0Q+3FACCAQAuAAQKf0EAAgQACQl6ImUGAPQCAAQACQl6ImUGAPQCAAAA.Darkarts:BAABLgAECn8nAAIIAAgJDCB0FQBrAgAIAAgJDCB0FQBrAgAAAA==.Darkblyte:BAAALgADCgEJAQAAAA==.Darkdaddy:BAABLgAECn8WAAINAAYJZx0yZQBTAQANAAYJZx0yZQBTAQAAAA==.Dartwo:BAAALgAECgcJEwAAAA==.',
De='Deadly:BAAALgAECgEJAwAAAA==.Deadlyshot:BAAALgAECgUJBwAAAA==.Deadlysniper:BAAALgADCgQJBAAAAA==.Deadnord:BAAALgAECgEJAQAAAA==.Deannisa:BAAALgAECgUJCAAAAA==.Deathmos:BAAALgADCgQJBAAAAA==.Deathshand:BAAALgADCgEJAQAAAA==.Debuffle:BAAALgADCgIJAgAAAA==.Deftonezz:BAAALgAECgYJBgAAAA==.Delecto:BAAALgADCgEJAQAAAA==.Delmônico:BAAALgADCgYJBgAAAA==.Dementedsage:BAAALgAECgEJAQAAAA==.Dendalaus:BAACLgAFFH8bAAIPAAYJ4CT9AgDsAQAPAAYJ4CT9AgDsAQAuAAQKfzwAAw8ACQkrJfcAAE8DAA8ACQkrJfcAAE8DAA4ABgngF60MAFYBAAAA.Denny:BAAALgAECgMJAwABLgAFFAUJEQAeALsSAA==.Denriak:BAAALgADCgcJGAAAAA==.Destoroyah:BAAALgADCgkJCQAAAA==.Desy:BAABLgAECn8XAAMIAAgJgiJlFQDVAgAIAAgJgiJlFQDVAgAHAAEJAADPZABFAAAAAA==.Devi:BAABLgAECn8mAAIKAAkJQh3ZBwDBAgAKAAkJQh3ZBwDBAgAAAA==.Devilsspawn:BAAALgADCgQJBAABLgAECgYJEwATAAAAAA==.Dewdadew:BAAALgAECgQJBAAAAA==.',
Di='Diddyb:BAAALgAECgkJCAAAAA==.Dimsumbun:BAABLgAECn8ZAAIIAAgJARHITgBwAQAIAAgJARHITgBwAQAAAA==.Dinklecold:BAAALgAECgEJAQAAAA==.Dinoxeye:BAABLgAECn8ZAAINAAgJPQukXgBkAQANAAgJPQukXgBkAQAAAA==.Dizzies:BAAALgAECgIJAwAAAA==.',
Do='Donmar:BAAALgADCgQJBAABLgAECggJJgAhABAdAA==.Donmu:BAABLgAECn8mAAIhAAgJEB1qDwAEAgAhAAgJEB1qDwAEAgAAAA==.Donncha:BAAALgADCgYJBgAAAA==.Donora:BAAALgADCggJCAABLgAECggJJgAhABAdAA==.Donut:BAAALgAECgUJBgAAAA==.Donyi:BAAALgADCgUJBQAAAA==.Donymo:BAAALgAECgYJBgAAAA==.Donzen:BAAALgADCgYJCwABLgAECggJJgAhABAdAA==.Dotholiday:BAABLgAECn8jAAQIAAgJqgvCXgBFAQAIAAgJqgvCXgBFAQAHAAEJAABWegAoAAAJAAEJAAAQLQAAAAAAAA==.Dotyoudead:BAAALgAECgcJDwAAAA==.',
Dr='Draacarys:BAAALgAECgYJBwAAAA==.Dramonk:BAACLgAFFH8aAAMhAAcJFBYOCABOAQAhAAUJXRgOCABOAQAKAAQJ0gjrHQDHAAAuAAQKfyAAAyEACQmcIOkIAOoCACEACAmkIukIAOoCAAoAAQn5DgZjAEQAAAAA.Drewmert:BAAALgAECgUJDQAAAA==.Druinlock:BAAALgAECgMJBwAAAA==.Drunknmonkey:BAAALgADCgMJAwAAAA==.',
Du='Dumpy:BAAALgADCgEJAQAAAA==.Dustybuds:BAABLgAECn8ZAAIBAAgJmBWvEgDeAQABAAgJmBWvEgDeAQAAAA==.Dustydrewid:BAAALgADCgEJAQAAAA==.',
Dw='Dwaynà:BAAALgAECgYJEwAAAA==.',
Dy='Dyre:BAABLgAECn8qAAIQAAkJ5xPSKwDdAQAQAAkJ5xPSKwDdAQAAAA==.Dyrefang:BAAALgADCggJCAAAAA==.',
['Dè']='Dèxx:BAAALgADCgEJAQABLgAECgEJAQATAAAAAA==.',
['Dë']='Dëxx:BAAALgADCgUJBQABLgAECgEJAQATAAAAAA==.',
Ed='Edam:BAAALgAECgQJBgAAAA==.Edgy:BAAALgADCgcJBwAAAA==.',
El='Elaris:BAAALgAECgMJBAAAAA==.Elementdeath:BAAALgAECggJCQAAAA==.Ellsnarl:BAAALgADCgYJCAAAAA==.Eltariel:BAAALgADCggJCwAAAA==.Elyiana:BAAALgAECgYJEAAAAA==.',
Em='Emeraldjin:BAACLgAFFH8KAAIKAAQJ9Qs3GgDvAAAKAAQJ9Qs3GgDvAAAuAAQKfyQAAwoACQnZF5QRACkCAAoACQnZF5QRACkCACEABAmdDQxGAJsAAAAA.Emeria:BAAALgADCgYJCAAAAA==.Emerialock:BAAALgAECgMJBAAAAA==.Emrots:BAAALgADCgEJAQAAAA==.',
En='Ensera:BAABLgAECn8bAAMcAAYJ/BQ0EQBsAQAcAAYJ/BQ0EQBsAQAdAAQJ3gpgKwDCAAAAAA==.Enslaved:BAAALgADCgIJAgAAAA==.Envymonkk:BAAALgAECgEJAQAAAA==.',
Eq='Equilibrium:BAAALgAECgEJAQABLgAECggJHgALAGofAA==.',
Es='Esdraa:BAABLgAECn8UAAIQAAcJow6hVQBHAQAQAAcJow6hVQBHAQAAAA==.',
Eu='Eugenekrabs:BAAALgADCgkJCQAAAA==.',
Ev='Evilbang:BAAALgADCgcJBwABLgAECgQJBgATAAAAAA==.',
Ex='Exstatic:BAAALgAECgUJBQAAAA==.Exton:BAAALgAECgIJAwAAAA==.Extraho:BAABLgAECn8eAAMWAAgJ4CEvCgCqAgAYAAgJdh8+BwC6AgAWAAcJyCEvCgCqAgAAAA==.',
Ez='Ezo:BAABLgAECn8cAAIGAAgJ1QwBLwBEAQAGAAgJ1QwBLwBEAQAAAA==.',
Fa='Fabed:BAAALgADCgYJBgAAAA==.Fabled:BAACLgAFFH8aAAQHAAcJvhqvBAANAQAHAAQJLRavBAANAQAIAAQJ6hBsIgD7AAAJAAMJHyOXBADDAAAuAAQKfyMAAwcACQk2I+4HAEcCAAcABglVIu4HAEcCAAgABgkUIgo3ADACAAAA.Faeyice:BAABLgAECn8oAAIPAAkJmQohFQChAQAPAAkJmQohFQChAQAAAA==.Falcondawn:BAAALgADCgYJCAAAAA==.Fat:BAAALgAECgQJCQAAAA==.Fatherfigure:BAAALgAECgIJCQAAAA==.',
Fe='Felbuttkick:BAAALgADCgEJAQABLgAFFAUJEgAPABEVAA==.Feldrie:BAAALgADCgEJAQABLgADCgIJAgATAAAAAA==.Femm:BAAALgAECgYJCwAAAA==.Feta:BAAALgADCgQJBAAAAA==.Feyden:BAABLgAECn8cAAIVAAYJURIPQgAoAQAVAAYJURIPQgAoAQAAAA==.Feärless:BAABLgAECn8bAAIEAAYJ6BguWACZAQAEAAYJ6BguWACZAQAAAA==.',
Ff='Ffxivcatgirl:BAAALgAFFAIJAgABLgAFFAcJGgAFAHIkAA==.',
Fi='Fijaswarerth:BAABLgAECn8gAAIBAAkJDyRCAQAzAwABAAkJDyRCAQAzAwAAAA==.Fijaswitcher:BAAALgAECgYJBwAAAA==.Filthy:BAAALgAECgkJBAAAAA==.Fimbulvargr:BAABLgAECn8oAAIFAAkJTxXVDADnAQAFAAkJTxXVDADnAQAAAA==.Fingerless:BAAALgAECgEJAgABLgAFFAMJCAANAFcMAA==.Finiith:BAACLgAFFH8VAAMKAAYJBAvXDQB/AQAKAAYJBAvXDQB/AQAhAAUJ/hRrCwAqAQAuAAQKfzMABCEACQmQIm8CABoDACEACQmQIm8CABoDABoABwltG0UmANIBAAoABAlwGEczABQBAAAA.Firedragonoo:BAAALgADCgUJBQAAAA==.Firegirl:BAAALgADCgUJBQAAAA==.',
Fl='Fluffykicks:BAAALgAECgUJDAAAAA==.Fluffyokami:BAABLgAECn8zAAIkAAgJch0ABQBPAgAkAAgJch0ABQBPAgAAAA==.Flugger:BAAALgAECgUJBQAAAA==.Fluggerblub:BAAALgAECgMJAwABLgAECgUJBQATAAAAAA==.',
Fo='Foehn:BAAALgADCgEJAQAAAA==.Fohl:BAABLgAECn8UAAIlAAYJ0wZNKwB9AAAlAAYJ0wZNKwB9AAAAAA==.Foneer:BAAALgAECgMJAwAAAA==.Fonkadin:BAAALgADCgUJBQAAAA==.Fooba:BAAALgAECgcJEgAAAA==.Forestsky:BAABLgAECn8oAAIEAAkJoRoCFQBaAgAEAAkJoRoCFQBaAgAAAA==.Foxybeast:BAAALgADCgEJAQAAAA==.',
Fr='Frenchieboi:BAABLgAECn8cAAIEAAgJwgxZVQA1AQAEAAgJwgxZVQA1AQAAAA==.Frenchielock:BAAALgAECgYJDQAAAA==.Frostbitedew:BAABLgAECn8YAAILAAYJwQkuoQD/AAALAAYJwQkuoQD/AAAAAA==.Frosttynips:BAAALgADCgYJBQAAAA==.Frozentears:BAAALgADCgcJBwAAAA==.',
Fu='Fullbuster:BAAALgAECgQJBgAAAA==.',
Ga='Galdiian:BAAALgADCgUJBQAAAA==.Galemoot:BAAALgAECgQJBAAAAA==.Gampo:BAAALgADCgUJBQAAAA==.',
Gh='Gherim:BAAALgADCgUJDQAAAA==.Ghosimoon:BAACLgAFFH8FAAMVAAIJ6wK1LABsAAAVAAIJxAK1LABsAAAkAAEJ7QHRBgBFAAAuAAQKfycAAyQABwmAGeoNANUBACQABwkaGOoNANUBABUABwn1FXwrAKYBAAAA.Ghyran:BAAALgAECgIJAgAAAA==.',
Gi='Gimixx:BAABLgAECn8dAAIlAAgJhB4lBwAjAgAlAAgJhB4lBwAjAgAAAA==.',
Gl='Glaivier:BAABLgAECn8lAAMEAAcJQBTYXgCEAQAEAAcJQBTYXgCEAQACAAEJdgzzJQAvAAAAAA==.Glavestation:BAAALgADCgYJDgAAAA==.Glitchdh:BAAALgAECgcJDwAAAA==.',
Go='Goregrind:BAACLgAFFH8ZAAMNAAYJax4jEAC5AQANAAUJax4jEAC5AQAFAAEJAADsMQAAAAAuAAQKf0EAAg0ACQmMJVwCAFwDAA0ACQmMJVwCAFwDAAAA.Gorius:BAAALgAECgUJBgAAAA==.',
Gr='Gravik:BAAALgADCgMJBgAAAA==.Gremory:BAABLgAECn8xAAIVAAgJpx/fCQBrAgAVAAgJpx/fCQBrAgAAAA==.Grimholt:BAAALgADCgYJBgAAAA==.Grommak:BAAALgADCgYJBgAAAA==.',
Gu='Guizee:BAACLgAFFH8GAAIMAAMJ7BP0FAABAQAMAAMJ7BP0FAABAQAuAAQKfxQAAgwABgk5HiAjAFkBAAwABgk5HiAjAFkBAAAA.Guretta:BAABLgAECn8oAAIBAAkJkxjLCAAjAgABAAkJkxjLCAAjAgAAAA==.',
Ha='Haeneros:BAABLgAECn8iAAICAAkJSw//CQBxAQACAAkJSw//CQBxAQAAAA==.Halokitty:BAAALgADCgYJCwAAAA==.Handmemytank:BAAALgAECggJDQABLgAFFAMJBwAQAEghAA==.Harumi:BAACLgAFFH8HAAIkAAMJ+AQBCADTAAAkAAMJ+AQBCADTAAAuAAQKfzoAAyQACAnEIxMCANICACQACAnEIxMCANICACUAAglSD/MpAFMAAAAA.Haveya:BAAALgAECgMJAwAAAA==.',
He='Heaf:BAAALgADCgIJAgABLgAECgcJEAATAAAAAA==.Heafk:BAAALgAECgYJEAABLgAECgcJEAATAAAAAA==.Heafstaag:BAAALgADCgQJBAABLgAECgcJEAATAAAAAA==.Healaribuff:BAAALgAECgQJBgABLgAECgkJHwAWADQUAA==.Heavyg:BAAALgAECgUJDAAAAA==.Hedgehog:BAABLgAECn87AAIKAAkJJCBnBgDjAgAKAAkJJCBnBgDjAgAAAA==.Heelwhoopya:BAAALgADCgkJFgAAAA==.Helious:BAAALgAECgEJAQAAAA==.Hellastupid:BAAALgADCgUJBQAAAA==.Hellsham:BAAALgAECgMJBAAAAA==.Hextrathicc:BAACLgAFFH8JAAIIAAQJnQwTPwAMAQAIAAQJnQwTPwAMAQAuAAQKfx8AAggACAkmF2pEAP4BAAgACAkmF2pEAP4BAAAA.Heywood:BAABLgAECn8WAAIQAAYJ9Q2EaQATAQAQAAYJ9Q2EaQATAQAAAA==.',
Hi='Hiddenmight:BAACLgAFFH8SAAIPAAUJERUFCwA8AQAPAAUJERUFCwA8AQAuAAQKfx0AAg8ACQkgHKYNAMICAA8ACQkgHKYNAMICAAAA.Hindü:BAAALgAECgQJCgAAAA==.',
Ho='Hogglefard:BAABLgAECn8dAAISAAgJeB46KACEAgASAAgJeB46KACEAgAAAA==.Holybuttkick:BAABLgAECn8kAAMSAAgJrCJwFQCEAgASAAgJnSBwFQCEAgAZAAgJ5R8XCABZAgABLgAFFAUJEgAPABEVAA==.Holycöw:BAAALgAECgEJAQAAAA==.Holyrei:BAAALgADCgYJCgAAAA==.Hons:BAACLgAFFH8RAAIEAAUJDCBhBQDTAQAEAAUJDCBhBQDTAQAuAAQKfyMAAgQACQkOJhMBANMDAAQACQkOJhMBANMDAAAA.Hotpawkets:BAAALgADCgcJEQAAAA==.Hotshocklett:BAAALgAECgQJBQAAAA==.',
Hu='Huneybunz:BAABLgAECn8kAAIlAAgJNQ9hFAA8AQAlAAgJNQ9hFAA8AQAAAA==.Hunglee:BAAALgADCgYJBwAAAA==.',
Ib='Ibis:BAAALgAECgUJBgAAAA==.',
Ic='Iceloving:BAAALgADCgEJAQABLgAFFAMJBgAPAJsWAA==.Ichci:BAAALgAECggJCAAAAA==.',
Id='Idomagic:BAAALgAECgMJBAAAAA==.',
Ig='Igne:BAAALgADCgEJAQAAAA==.Igniting:BAABLgAECn8VAAILAAYJ9wipowD6AAALAAYJ9wipowD6AAABLgAECgcJJQAEAEAUAA==.',
Ik='Ikillyoutoo:BAAALgAECgYJBgAAAA==.',
Im='Implant:BAACLgAFFH8cAAIUAAcJWSTqAADlAgAUAAcJWSTqAADlAgAuAAQKfx8AAxQACQkhJSMBAKMDABQACQkhJSMBAKMDABUAAwmnITJHABEBAAAA.Impression:BAAALgADCgYJBgABLgAFFAcJHAAUAFkkAA==.Impweaver:BAAALgADCgkJFQABLgAFFAcJHAAUAFkkAA==.',
In='Incarnated:BAAALgAECgEJAQABLgAECgkJGQAEACocAA==.Incursion:BAABLgAECn8kAAIRAAkJTB1LCQCwAgARAAkJTB1LCQCwAgAAAA==.Inelor:BAAALgAECgEJAQABLgAECggJHgALAGofAA==.Infused:BAAALgADCgQJBAAAAA==.',
Io='Ioboma:BAAALgADCgYJBgAAAA==.',
Ir='Ironwolf:BAABLgAECn8zAAIBAAkJ6RSgCwDlAQABAAkJ6RSgCwDlAQAAAA==.',
Is='Isharuu:BAAALgAECggJDwAAAA==.',
Iv='Ivanka:BAAALgAECgEJAQAAAA==.',
Ja='Jabbawockey:BAACLgAFFH8FAAIEAAMJ5x3CMAAUAQAEAAMJ5x3CMAAUAQAuAAQKfxgAAgQACQmOHmoLALMCAAQACQmOHmoLALMCAAAA.Jackpot:BAAALgAECgUJBgAAAA==.Jademoot:BAABLgAECn8UAAIKAAgJtBKDLQA3AQAKAAgJtBKDLQA3AQAAAA==.Jaden:BAABLgAECn8iAAIGAAgJnRrcGQDQAQAGAAgJnRrcGQDQAQAAAA==.Jaeaoria:BAAALgAECgIJAwAAAA==.Janoria:BAABLgAECn8VAAIWAAYJxxzhFgDPAQAWAAYJxxzhFgDPAQAAAA==.Jaxurbate:BAAALgAECgEJAQAAAA==.Jaylaah:BAAALgAECgcJCgAAAA==.Jayvlyn:BAABLgAECn8WAAIjAAkJ0As4JgBhAQAjAAkJ0As4JgBhAQAAAA==.',
Ji='Jiinn:BAABLgAECn8aAAIZAAcJbRLBFAAsAQAZAAcJbRLBFAAsAQAAAA==.',
Jj='Jjman:BAAALgAECgcJCAABLgAECgkJCgATAAAAAA==.Jjuicyfruit:BAAALgAECgMJCgAAAA==.',
Jo='Joftokal:BAABLgAECn8kAAIiAAgJ6hOYCQC9AQAiAAgJ6hOYCQC9AQAAAA==.Joranji:BAAALgADCgUJBQAAAA==.Jorvik:BAAALgAECgEJAQAAAA==.Jovick:BAAALgADCgQJBAAAAA==.Joyboy:BAABLgAECn85AAMRAAkJSSXjBwDwAgARAAkJSSXjBwDwAgASAAgJVRIGUwCGAQAAAA==.',
Jp='Jpgalloway:BAAALgAECgQJBAAAAA==.',
Ju='Judeau:BAAALgAECgEJAQAAAA==.Jueya:BAAALgAECgYJEAAAAA==.',
Ka='Kalenex:BAAALgADCgkJGAAAAA==.Kalim:BAAALgAECgcJEwAAAA==.Kargran:BAAALgAECgUJDQAAAA==.Kargrug:BAAALgADCgYJBgAAAA==.Katherinne:BAAALgAECgMJAwAAAA==.Kattle:BAACLgAFFH8GAAIiAAUJjA0EBQAhAQAiAAUJjA0EBQAhAQAuAAQKf0EAAiIACQmbJGoAAEoDACIACQmbJGoAAEoDAAAA.',
Ke='Keisero:BAAALgADCgQJBAAAAA==.Keyrasky:BAAALgAECgUJBQAAAA==.',
Kh='Khailyn:BAAALgADCggJDAAAAA==.Kharrock:BAAALgADCgcJBwAAAA==.Khrysus:BAABLgAECn8XAAMHAAkJCxQYCgBRAQAHAAcJchQYCgBRAQAIAAcJoAjdsgDzAAAAAA==.',
Ki='Kidkill:BAAALgAECgUJCgAAAA==.Kikuu:BAABLgAECn82AAMZAAcJBRw4CgDRAQAZAAcJBRw4CgDRAQASAAIJ3wd8IAFcAAAAAA==.Killadin:BAABLgAECn8jAAISAAgJ9A3XYgBfAQASAAgJ9A3XYgBfAQAAAA==.Killian:BAAALgADCgMJAwAAAA==.Kitå:BAEBLgAECn85AAMeAAcJqiCLDwCEAgAeAAcJqiCLDwCEAgAjAAYJeR1LHQChAQAAAA==.',
Kl='Kloud:BAAALgAECgcJBwABLgAECgUJBgATAAAAAA==.',
Kn='Knoks:BAABLgAECn8jAAQHAAkJHRouDAAtAQAIAAUJhxiRTAB2AQAHAAYJAxYuDAAtAQAJAAEJsx9DIQBHAAAAAA==.Knotty:BAAALgAECgEJAgAAAA==.Knuckleup:BAAALgADCgYJBgABLgAECgQJCwATAAAAAA==.',
Ko='Koff:BAACLgAFFH8cAAIKAAYJyiPFAwBJAgAKAAYJyiPFAwBJAgAuAAQKfyoAAgoACQnTJjIAAO4DAAoACQnTJjIAAO4DAAAA.Koreshei:BAAALgAECgYJEAAAAA==.Kothar:BAAALgADCggJHAAAAA==.',
Kr='Krelara:BAAALgAECgcJCAAAAA==.Krenerokos:BAAALgAECgcJDwAAAA==.Kruxvoidscar:BAAALgADCgcJBwAAAA==.',
Ku='Kungfuchino:BAAALgADCgQJBwAAAA==.Kuni:BAAALgAFFAMJBgAAAQ==.Kural:BAAALgADCgkJDwAAAA==.Kurius:BAAALgAECgIJAgAAAA==.',
Kw='Kwille:BAAALgADCgEJAQAAAA==.',
Ky='Kyleskitten:BAAALgAECgYJBgAAAA==.Kylian:BAACLgAFFH8GAAINAAMJpwhQbgDXAAANAAMJpwhQbgDXAAAuAAQKfx4AAw0ACQmpFytMAJYBAA0ACQleFCtMAJYBACYABgnGFqQHAH8BAAAA.Kynthina:BAAALgADCgIJAgAAAA==.Kyouk:BAAALgADCgcJCgAAAA==.',
Kz='Kz:BAAALgAECgUJBQAAAA==.',
La='Ladrious:BAAALgAECgQJBQAAAA==.Lamynx:BAAALgAECgQJCwAAAA==.Landarel:BAAALgADCgIJAgABLgADCgIJFAATAAAAAA==.Lanestina:BAAALgADCgMJAwAAAA==.Larinstore:BAAALgAECgkJBAAAAA==.Lawctor:BAABLgAECn8hAAIRAAkJ8xVSGgDmAQARAAkJ8xVSGgDmAQAAAA==.Lawordan:BAAALgAECgQJBwAAAA==.Laylã:BAAALgADCgQJBAAAAA==.Lazydragon:BAABLgAECn8dAAMSAAgJoxJvTQCVAQASAAgJoxJvTQCVAQAZAAcJHQa8IQCwAAAAAA==.Lazypotato:BAAALgADCgEJAQABLgAECgUJDAATAAAAAA==.',
Le='Leatherbelt:BAAALgAECgYJCgAAAA==.Leebruce:BAABLgAECn8dAAMaAAkJehXAFQC/AQAaAAkJBxLAFQC/AQAhAAUJbRkuLAB+AQAAAA==.Leoella:BAAALgAECgYJDAAAAA==.Leone:BAABLgAECn8oAAINAAkJ3R67GABvAgANAAkJ3R67GABvAgAAAA==.',
Li='Liberation:BAABLgAECn8oAAIEAAgJuBlKJAD2AQAEAAgJuBlKJAD2AQAAAA==.Lickapop:BAAALgAECgUJCwAAAA==.Lileda:BAAALgADCgcJEwAAAA==.Lilgirlblue:BAABLgAECn8fAAIQAAgJRww4SgBpAQAQAAgJRww4SgBpAQAAAA==.Lilvoids:BAABLgAECn8aAAMIAAgJZwwqVgBbAQAIAAcJPwsqVgBbAQAHAAMJ9gk0RwCZAAAAAA==.Lilwang:BAAALgADCgUJBQAAAA==.Lion:BAAALgAECgcJEgAAAA==.Littlelight:BAAALgAECgEJAgAAAA==.Livray:BAAALgADCgMJBAAAAA==.',
Ll='Llyolis:BAAALgAECgMJBgABLgAECgQJCwATAAAAAA==.',
Ln='Lnetrapx:BAAALgAFFAEJAQABLgAFFAQJAQATAAAAAA==.',
Lo='Lockalicious:BAAALgADCgYJCgAAAA==.Lolipop:BAAALgADCgQJBAAAAA==.Lonepanda:BAACLgAFFH8bAAIBAAYJ8x/RAgDNAQABAAYJ8x/RAgDNAQAuAAQKf0EAAwEACQkfJDQBADUDAAEACQkfJDQBADUDAAYABwmuGaQxAOYBAAAA.Loriella:BAACLgAFFH8TAAIUAAYJdw6gDACoAQAUAAYJdw6gDACoAQAuAAQKf0UAAhQACQl3I9wBAJUDABQACQl3I9wBAJUDAAAA.Lorstus:BAAALgADCggJCQAAAA==.',
Lu='Luciliv:BAAALgAECgUJCQAAAA==.Lucille:BAAALgAECgYJDwAAAA==.Lunabomb:BAAALgADCgIJAgAAAA==.Lupinaea:BAAALgAECgEJAQAAAA==.',
Ly='Lylithh:BAAALgADCgMJAwAAAA==.',
['Lí']='Lílith:BAAALgAECgQJDwAAAA==.',
Ma='Maalk:BAABLgAECn8eAAMjAAgJZRjgIAAIAgAjAAcJIhzgIAAIAgAeAAcJNg8JTABTAQAAAA==.Mabellah:BAAALgADCgYJCQAAAA==.Maemikyu:BAABLgAECn81AAIWAAkJnCHiBgDfAgAWAAkJnCHiBgDfAgAAAA==.Magebuttkick:BAAALgAECgQJBAABLgAFFAUJEgAPABEVAA==.Magusultimis:BAABLgAECn8YAAILAAcJ6wPTrgDnAAALAAcJ6wPTrgDnAAAAAA==.Mahöshöjo:BAAALgAECgcJDQAAAA==.Makaveli:BAAALgAECgQJCAAAAA==.Makepoop:BAABLgAECn8bAAIMAAkJqB7UEAB6AgAMAAkJqB7UEAB6AgAAAA==.Malatia:BAAALgAECgEJAQABLgAECgYJDQATAAAAAA==.Marbared:BAABLgAECn8dAAISAAcJJxb+WAB3AQASAAcJJxb+WAB3AQAAAA==.Mardukdew:BAAALgADCgEJAQAAAA==.Marianita:BAAALgAECgQJCgAAAA==.Marlb:BAABLgAECn8YAAILAAgJZxLLhwDCAQALAAgJZxLLhwDCAQAAAA==.Marvolio:BAAALgADCgQJBAAAAA==.Masharo:BAAALgADCgcJBwAAAA==.Mastaßlasta:BAAALgADCgMJAwAAAA==.Mathranis:BAAALgADCgUJBQABLgAECgcJEwATAAAAAA==.',
Me='Mechasxz:BAAALgADCgEJAQAAAA==.Mediarahan:BAABLgAECn8tAAIeAAgJExsjFwA8AgAeAAgJExsjFwA8AgAAAA==.Melfist:BAABLgAECn8aAAQhAAYJnxH3LwD4AAAhAAYJfRD3LwD4AAAaAAYJzA2yNADvAAAKAAQJ7gIpXgBXAAAAAA==.Menara:BAAALgAECgcJCwAAAA==.Mercia:BAABLgAECn8WAAIEAAYJVBJWYgARAQAEAAYJVBJWYgARAQAAAA==.',
Mi='Michimichi:BAAALgADCgIJAgAAAA==.Mikiko:BAABLgAECn8aAAIjAAcJeg79MwARAQAjAAcJeg79MwARAQAAAA==.Millcreek:BAABLgAECn8aAAMkAAgJEBL5DACHAQAkAAgJEBL5DACHAQAUAAUJNwmBhwDHAAAAAA==.Mimiruu:BAAALgADCgIJAgAAAA==.Miniøn:BAAALgAECgYJBgAAAA==.Missindragon:BAABLgAECn8kAAIeAAgJhhrJFQBIAgAeAAgJhhrJFQBIAgAAAA==.Mistical:BAAALgADCgcJBwABLgAECgYJEAATAAAAAA==.Mistyelliott:BAAALgAECgYJDgABLgAECgkJHwAWADQUAA==.Misu:BAAALgAECgcJBwAAAA==.Mitikai:BAAALgADCgQJBAAAAA==.Mizhealin:BAAALgAECgEJAQAAAA==.Mizoafe:BAAALgADCgQJBAAAAA==.Mizof:BAAALgAECgMJBAAAAA==.Mizofee:BAAALgAECgEJAgAAAA==.Mizofer:BAAALgAECgIJBAAAAA==.',
Mn='Mntdew:BAAALgADCgIJAgAAAA==.',
Mo='Moarass:BAABLgAECn8zAAIKAAgJPxoDEQAwAgAKAAgJPxoDEQAwAgAAAA==.Mogrokrim:BAAALgAECgEJAQAAAA==.Moistyman:BAABLgAECn8cAAIKAAkJHRA0HwChAQAKAAkJHRA0HwChAQAAAA==.Mojogrippy:BAABLgAECn8sAAINAAkJ0iMWCAD+AgANAAkJ0iMWCAD+AgAAAA==.Molson:BAAALgAECgQJBAAAAA==.Monkeyfu:BAAALgAECgEJAQAAAA==.Monkuo:BAAALgAECgMJBAAAAA==.Moomoohead:BAAALgAECgcJBwAAAA==.Moondrie:BAAALgADCgIJAgAAAA==.Morcaila:BAAALgAECgQJCAAAAA==.Mordif:BAAALgAECgMJAwAAAA==.Morguein:BAAALgAFFAEJAQABLgAFFAUJHQANAC0eAA==.Mormel:BAABLgAECn8mAAIkAAkJfhUQBgAsAgAkAAkJfhUQBgAsAgAAAA==.Mormonmom:BAAALgADCgEJAQAAAA==.Morticus:BAAALgADCgMJAwAAAA==.Motspur:BAABLgAECn8aAAMhAAcJnAVrTgDYAAAaAAYJygVHVQDvAAAhAAYJCARrTgDYAAAAAA==.Motteraxz:BAAALgAECgYJEwAAAA==.Mourgrim:BAAALgAECgIJAgAAAA==.',
My='Mydland:BAAALgADCgQJBAAAAA==.Mythicc:BAAALgADCgQJBAAAAA==.',
['Mà']='Màní:BAAALgADCgIJAgAAAA==.',
Na='Nall:BAAALgADCgIJAgAAAA==.Nalliella:BAABLgAECn8YAAMGAAgJRwiCYwAkAQAGAAgJMgiCYwAkAQABAAEJpANYSwAmAAAAAA==.Namelesshymn:BAAALgADCgIJAwAAAA==.Naomill:BAAALgAECgEJAQAAAA==.Narial:BAAALgAECgMJAwAAAA==.Narru:BAACLgAFFH8QAAMnAAYJVRbgAwCOAQAnAAYJ+QvgAwCOAQAQAAMJGB0eCQAYAQAuAAQKfzsABBAACQkOJXYFADUDABAACAkSJHYFADUDACcACQk0IjYCAPsCACAABgm+D71GADkBAAAA.Nawah:BAAALgAECgEJAwAAAA==.Naztee:BAABLgAECn8XAAISAAYJwiLwOwA0AgASAAYJwiLwOwA0AgAAAA==.',
Ne='Nebyula:BAABLgAECn8rAAIWAAgJ5SI/BAAGAwAWAAgJ5SI/BAAGAwAAAA==.Neccrofeelya:BAAALgAECgYJCQABLgAECgcJDgATAAAAAA==.Neccrom:BAAALgAECgcJDgAAAA==.Necrovis:BAAALgAECgMJBgAAAA==.Nekochaos:BAAALgAECgEJAQAAAA==.Nephylem:BAAALgADCgEJAQAAAA==.Nevervister:BAAALgADCgUJBQAAAA==.',
Ni='Nightcrwler:BAAALgAECgEJAgAAAA==.Nirathen:BAAALgADCgMJAwABLgADCgUJBwATAAAAAA==.',
No='Nokim:BAAALgAECggJEQAAAA==.Norieka:BAABLgAECn8cAAISAAcJSxZJVgB+AQASAAcJSxZJVgB+AQAAAA==.Northumbria:BAAALgAECgEJAQABLgAECgYJFgAEAFQSAA==.Noskillidan:BAACLgAFFH8WAAIEAAYJqhMCFgB7AQAEAAYJqhMCFgB7AQAuAAQKf00AAwQACQmcIxEDADQDAAQACQmcIxEDADQDAAMABgmvDTQ2AC4BAAAA.Nosral:BAAALgAECgQJBQAAAA==.Nothgiel:BAAALgADCgcJBwAAAA==.Notvegan:BAACLgAFFH8FAAIeAAMJdxPRKgDaAAAeAAMJdxPRKgDaAAAuAAQKfxoAAx4ACQkHFi0sANsBAB4ACQkHFi0sANsBACMAAQksCdB/ACgAAAAA.',
Nr='Nrizzle:BAAALgAECgEJAQAAAA==.',
Nu='Numinous:BAAALgAECgEJAQABLgAECgkJLwAGAFsdAA==.',
Ny='Nykoleus:BAABLgAECn82AAQJAAkJuhuEAgBDAgAJAAkJuhuEAgBDAgAIAAEJBwJ3LgEjAAAHAAEJ8wFjfQAhAAAAAA==.Nyste:BAABLgAECn8lAAINAAgJnRNVRwClAQANAAgJnRNVRwClAQAAAA==.',
Od='Odeliah:BAAALgADCgYJBgAAAA==.Odell:BAAALgADCgUJCAAAAA==.Odinn:BAAALgAECgcJEQAAAA==.',
Oo='Oopsidiéd:BAAALgAECggJDgAAAA==.',
Or='Orionpax:BAAALgAECgQJCQAAAA==.Orionsson:BAAALgADCgEJAQAAAA==.',
Os='Osò:BAAALgAECgYJEQAAAA==.',
Pa='Pallygranny:BAEALgAECgcJCAABLgADCgEJAQATAAAAAA==.Pandaboi:BAAALgAECgMJBgAAAA==.Pandapri:BAABLgAECn8cAAQYAAcJBR8QCwCGAgAYAAcJ2B4QCwCGAgAWAAQJ4hefTAAGAQAMAAIJaA7QWgBMAAAAAA==.Parisher:BAAALgADCgEJAQAAAA==.Passivetréé:BAAALgAECgMJBAAAAA==.Patron:BAAALgAFFAEJAQABLgAFFAMJCAANAFcMAA==.Pawnisher:BAAALgADCgMJAwAAAA==.',
Pe='Peaceviper:BAAALgADCgkJEAAAAA==.Pelitiera:BAAALgADCgQJBAAAAA==.Perkyy:BAAALgADCgMJAwAAAA==.',
Ph='Philosophic:BAAALgAECgMJBAAAAA==.Phreakoff:BAAALgADCgEJAQAAAA==.Phyntom:BAAALgAECggJCgAAAA==.',
Pi='Pibbs:BAACLgAFFH8OAAILAAUJlSD6JgBqAQALAAUJlSD6JgBqAQAuAAQKfyQAAgsACAm6Iw8UADADAAsACAm6Iw8UADADAAAA.',
Pl='Plaguebloom:BAAALgAECgEJAQABLgAECgkJHwAkAL8iAA==.Pleaseclap:BAAALgAECggJDwAAAA==.',
Po='Poose:BAAALgAECgQJCAABLgAECgYJDQATAAAAAA==.Poppatroll:BAAALgAECgQJCQAAAA==.Porsche:BAABLgAECn8bAAISAAgJ9h2qHgCzAgASAAgJ9h2qHgCzAgAAAA==.Potato:BAAALgAECgUJCwAAAA==.',
Pr='Prev:BAAALgAECgIJAgAAAA==.Prevention:BAAALgAECgcJCQAAAA==.Priestologyy:BAAALgADCgUJBQAAAA==.Protagoras:BAAALgADCgIJAgAAAA==.Prsera:BAAALgADCgkJCQABLgAECgYJGwAcAPwUAA==.',
Pu='Pulsar:BAAALgADCgkJCQABLgAECgYJCgATAAAAAA==.',
Py='Pyreanda:BAAALgADCgEJAQAAAA==.Pyrocalypse:BAAALgADCgUJBwAAAA==.',
['Pã']='Pãndâ:BAAALgAFFAIJBAAAAA==.',
Ra='Raerra:BAAALgAECgQJBAAAAA==.Rafig:BAACLgAFFH8bAAILAAYJhSOdDAD0AQALAAYJhSOdDAD0AQAuAAQKf0EAAwsACQlyJTAFADsDAAsACQlfJTAFADsDABcABQk8I8gGAKQBAAAA.Rahtoo:BAAALgADCgYJBgAAAA==.Ralii:BAABLgAECn8lAAIVAAkJYxuODQAvAgAVAAkJYxuODQAvAgAAAA==.Ralobii:BAAALgAECgMJAwABLgAECgkJJQAVAGMbAA==.Ramses:BAACLgAFFH8bAAIjAAYJ8gvBDABcAQAjAAYJ8gvBDABcAQAuAAQKfz8AAiMACQlDHgEIAJkCACMACQlDHgEIAJkCAAAA.Rasmodeus:BAAALgAECgMJBAAAAA==.Rats:BAAALgAECgMJBQAAAA==.Rayy:BAAALgAECgUJCgAAAA==.',
Re='Redhood:BAAALgAECgUJCAAAAA==.Reformed:BAAALgAECggJEwABLgAFFAQJDgAEAHIaAA==.Regoran:BAAALgADCgIJAgAAAA==.Reinerbraun:BAAALgAECgYJCwAAAA==.Renade:BAAALgAECgcJEAAAAA==.Reshape:BAAALgADCgMJAwABLgADCgcJDAATAAAAAA==.Restitution:BAAALgAECgMJBgAAAA==.Retdaddy:BAAALgAECgQJCgAAAA==.Return:BAAALgADCgYJBgAAAA==.Rewellus:BAAALgADCgMJBAAAAA==.Rexx:BAAALgAECgQJBAAAAA==.',
Rh='Rhazzah:BAAALgAECgQJBAABLgAECggJEgATAAAAAA==.',
Ri='Rigidsxz:BAAALgAECgcJCgAAAA==.Riona:BAAALgAECgEJAQABLgAFFAQJCQAIAJ0MAA==.Riskyshammy:BAABLgAECn8xAAIeAAkJFx/aCgC/AgAeAAkJFx/aCgC/AgAAAA==.Ritapoon:BAAALgADCgYJBwAAAA==.Riteaid:BAAALgAECgUJCQAAAA==.',
Ro='Rocfeather:BAABLgAECn8VAAIGAAcJhQrCNAAmAQAGAAcJhQrCNAAmAQAAAA==.Rocmage:BAAALgADCgIJAgAAAA==.Rodolfblanne:BAABLgAECn8VAAMGAAYJdQTGUgCoAAAGAAYJ+QPGUgCoAAAfAAQJzAP6MgBmAAAAAA==.Rokushichi:BAAALgADCgIJAwABLgAECgkJOwAKACQgAA==.Roll:BAAALgAECgUJCAAAAA==.Ronok:BAABLgAECn8cAAIGAAgJNBpmGwBxAgAGAAgJNBpmGwBxAgAAAA==.Rootz:BAAALgAECgYJDAAAAA==.Rorthach:BAAALgAECgYJDAAAAA==.Roseire:BAAALgAECgQJBgAAAA==.Rosemoon:BAAALgAECgEJAgAAAA==.Rosethebrute:BAABLgAECn8nAAIGAAcJoRyqJQAsAgAGAAcJoRyqJQAsAgAAAA==.Rosetheholy:BAAALgAECgQJBAABLgAECgcJJwAGAKEcAA==.Rougeloving:BAACLgAFFH8GAAIPAAMJmxaJGAD3AAAPAAMJmxaJGAD3AAAuAAQKfx0AAg8ABwlvIBIOAPcBAA8ABwlvIBIOAPcBAAAA.Roushi:BAABLgAECn8xAAIaAAgJNySsBADHAgAaAAgJNySsBADHAgAAAA==.',
Ru='Ruler:BAAALgAECgUJCwAAAA==.Rules:BAAALgAECgUJCAAAAA==.Ruli:BAABLgAECn80AAIQAAkJ+hhwHwAbAgAQAAkJ+hhwHwAbAgAAAA==.Rusticdiino:BAAALgAECgYJCwABLgAECgcJBwATAAAAAA==.Ruvia:BAAALgAECgIJBQAAAA==.Ruyhunter:BAAALgADCgEJAQABLgAECgQJBgATAAAAAA==.',
Ry='Ryshin:BAACLgAFFH8KAAMPAAMJyhVSGQDxAAAPAAMJeBVSGQDxAAAOAAEJIgpHDABOAAAuAAQKfzgAAw4ACAnsHNUIAHABAA8ACAk7FzgcAB0CAA4ACAmIGNUIAHABAAAA.',
['Ré']='Réxx:BAAALgAFFAMJBAAAAA==.',
['Rö']='Rörs:BAAALgADCgYJBgAAAA==.',
['Rø']='Røøster:BAAALgAECgQJBwAAAA==.',
Sa='Sabeck:BAAALgAECgkJCgAAAA==.Sacrébrew:BAAALgAFFAEJAwAAAA==.Safi:BAABLgAECn8fAAIjAAkJ1hTtFgDaAQAjAAkJ1hTtFgDaAQAAAA==.Saltine:BAEALgADCgcJDQABLgAECgkJOQAeAKogAA==.Sanctano:BAABLgAECn8uAAMRAAkJeB/ZCwC+AgARAAkJeB/ZCwC+AgASAAYJEBa1bQBHAQAAAA==.Sapdo:BAAALgAECgEJAQABLgAECgEJAQATAAAAAA==.Sar:BAAALgADCgUJBQAAAA==.Sarrath:BAAALgAECgMJBAAAAA==.Saticdh:BAAALgAECgIJAgAAAA==.Saurfang:BAAALgADCgcJBwAAAA==.Savagesage:BAACLgAFFH8KAAIQAAMJ9hd/LwD+AAAQAAMJ9hd/LwD+AAAuAAQKfyYAAxAACAnTIm0OAMgCABAACAnTIm0OAMgCACAABAnVC5VkAK4AAAAA.Saylavee:BAAALgADCgYJCQAAAA==.Sayn:BAACLgAFFH8IAAISAAMJXhnbNAAIAQASAAMJXhnbNAAIAQAuAAQKfx0AAhIACAn2I8IQAKYCABIACAn2I8IQAKYCAAAA.',
Sc='Scalyy:BAABLgAECn8XAAIbAAkJaiLqAgAjAwAbAAkJaiLqAgAjAwABLgAFFAUJFAAMAJgjAA==.Scarringpain:BAAALgADCgYJBgAAAA==.Schultzies:BAAALgAECgQJBwABLgAECggJGgANABIPAA==.Sconestorm:BAAALgAECgQJBQAAAA==.',
Sd='Sdog:BAAALgAECgQJBAAAAA==.',
Se='Seanboyylzps:BAABLgAECn8VAAIWAAYJ9huCFwDIAQAWAAYJ9huCFwDIAQABLgAECggJIwALAF8YAA==.Seanboyymage:BAABLgAECn8jAAMLAAgJXxh7OwDqAQALAAgJXxh7OwDqAQAXAAQJPhODDQDwAAAAAA==.Seina:BAABLgAECn8oAAIfAAkJYxdwBwAuAgAfAAkJYxdwBwAuAgAAAA==.Selohssa:BAAALgADCgMJAwAAAA==.Selvara:BAAALgADCgYJAwAAAA==.Sensei:BAABLgAECn8ZAAIPAAgJ9A79HgADAgAPAAgJ9A79HgADAgAAAA==.Sep:BAABLgAECn8iAAIFAAkJkRPPEQCZAQAFAAkJkRPPEQCZAQAAAA==.Seraphymm:BAAALgAECgMJBAAAAA==.Setup:BAAALgADCgEJAQAAAA==.',
Sh='Shammydavis:BAAALgAECgQJCAAAAA==.Shammyspoons:BAACLgAFFH8aAAMjAAYJnR33AwCmAQAjAAUJsiP3AwCmAQAeAAIJHQxiOwCRAAAuAAQKfxgAAiMACAltIv0IAAIDACMACAltIv0IAAIDAAAA.Shampayn:BAAALgADCgYJBgAAAA==.Shamshiel:BAAALgADCgUJBQAAAA==.Shanke:BAAALgAECgYJCwABLgAECgYJDQATAAAAAA==.Shankee:BAAALgADCgYJCwAAAA==.Shankiee:BAAALgAECgQJCAAAAA==.Shanti:BAABLgAECn8dAAMhAAkJ7g1cHgBpAQAhAAkJ7g1cHgBpAQAKAAUJJgjkRwC6AAAAAA==.Shaynke:BAAALgAECgQJBAABLgAECgYJDQATAAAAAA==.Shaynkee:BAAALgAECgQJBwAAAA==.Shenvin:BAAALgADCgcJBwAAAA==.Shiroompa:BAAALgADCgYJBgAAAA==.Shrìke:BAAALgAECgcJDQABLgADCgIJFAATAAAAAA==.Shupasins:BAACLgAFFH8HAAIiAAMJDhgHBgD5AAAiAAMJDhgHBgD5AAAuAAQKfxcAAyIACQmuGgcFAEUCACIACAk8HAcFAEUCAB4AAwktDB2JAFEAAAAA.Shupshifta:BAAALgAECgQJBAAAAA==.Shyamablue:BAAALgAECgYJBgAAAA==.',
Si='Silëñt:BAAALgAECggJDwAAAA==.Simphoid:BAAALgADCgcJBwAAAA==.Simpleyfire:BAAALgAECgcJBwAAAA==.Sinadin:BAAALgADCgQJBAAAAA==.Sindraylea:BAABLgAECn8kAAMNAAgJJB+kIwAwAgANAAgJJB+kIwAwAgAFAAEJ7hbZQAA+AAAAAA==.Sithkill:BAAALgAECggJEgAAAA==.',
Sk='Skelahoe:BAAALgADCgQJBAAAAA==.Skreebo:BAAALgADCgIJAgAAAA==.Skândranon:BAAALgADCgEJAQAAAA==.Skÿ:BAAALgAECgUJBwAAAA==.',
Sl='Slurpee:BAABLgAECn8uAAILAAgJvhpCMQASAgALAAgJvhpCMQASAgAAAA==.',
Sn='Sneekypete:BAAALgAECgYJDQAAAA==.',
So='Sorin:BAAALgADCgMJBgAAAA==.Sorscha:BAABLgAECn8aAAMCAAgJPx6wBgDOAQACAAYJiiCwBgDOAQAEAAcJkReyPQCEAQAAAA==.Sourdough:BAAALgADCgkJDAAAAA==.',
Sp='Spacekraken:BAAALgADCgYJBgAAAA==.Spammy:BAABLgAECn8nAAMRAAkJERFEGwDdAQARAAkJERFEGwDdAQASAAYJCxRWfAAqAQAAAA==.Sparlyy:BAACLgAFFH8UAAIMAAUJmCMkBwCNAQAMAAUJmCMkBwCNAQAuAAQKfy8AAgwACAlcJtoDAO8CAAwACAlcJtoDAO8CAAAA.Sparticus:BAAALgADCgUJBQAAAA==.Spoonsworn:BAACLgAFFH8GAAIIAAQJlg7PJQDqAAAIAAQJlg7PJQDqAAAuAAQKfyAAAwgACAkoIP8gACICAAgACAkoIP8gACICAAcAAwmRFY43ANcAAAAA.',
Ss='Sswordy:BAACLgAFFH8bAAIQAAYJOhNoBgCmAQAQAAYJOhNoBgCmAQAuAAQKf00AAhAACQlEIzAEABsDABAACQlEIzAEABsDAAAA.',
St='Stavissia:BAAALgADCggJCAAAAA==.Stimulus:BAABLgAECn8gAAIYAAgJpgZwIwBUAQAYAAgJpgZwIwBUAQAAAA==.Stonedmom:BAAALgAECgQJBQAAAA==.Stormfang:BAABLgAECn8VAAIiAAgJGwZjEQAkAQAiAAgJGwZjEQAkAQAAAA==.Straathond:BAAALgADCgEJAQABLgAECgkJKAARAG0bAA==.',
Su='Suetonius:BAAALgAECgEJAQAAAA==.Sulfogan:BAABLgAECn8ZAAMNAAYJXxrQXQBmAQANAAYJXxrQXQBmAQAFAAIJhAdaPABPAAABLgAECggJGAALAGcSAA==.Sunflora:BAAALgADCgMJBwAAAA==.Sunkist:BAAALgAECgQJBAAAAA==.Sunnidi:BAABLgAECn8kAAIVAAkJSw6zGwCRAQAVAAkJSw6zGwCRAQAAAA==.Sunwell:BAAALgAECgQJBwAAAA==.Sureina:BAAALgAECgcJCAAAAA==.Surlym:BAABLgAECn8wAAIKAAkJkx6NBwDIAgAKAAkJkx6NBwDIAgAAAA==.Suunny:BAAALgADCgEJAQAAAA==.Suzuka:BAAALgAECgEJAQAAAA==.',
Sw='Switchfoot:BAAALgADCgMJAwABLgAFFAIJBQADAIILAA==.Switchglaive:BAACLgAFFH8FAAIDAAIJgguPEwCSAAADAAIJgguPEwCSAAAuAAQKfyUAAwMACAnsGFIYAAUCAAMACAnsGFIYAAUCAAIABAkbDMoXAJYAAAAA.',
Sy='Sylvania:BAAALgAECgUJBQAAAA==.Symphoid:BAAALgAECgUJCAAAAA==.Symphoidd:BAAALgADCgYJBgAAAA==.Syndere:BAAALgADCgYJCAAAAA==.Syrasmine:BAAALgADCgYJBwAAAA==.Syseloris:BAABLgAECn8mAAICAAkJbh//AgBvAgACAAkJbh//AgBvAgAAAA==.Sythion:BAABLgAFFH8GAAIcAAMJBwUJGQCjAAAcAAMJBwUJGQCjAAABLgAFFAQJCAAIAIkUAA==.',
['Sâ']='Sâlisbury:BAAALgADCgYJCgAAAA==.',
['Së']='Sëphy:BAAALgAECgYJEwAAAA==.',
Ta='Tabdotwin:BAABLgAECn8WAAQIAAcJgRiOWgC4AQAIAAcJgRiOWgC4AQAHAAIJpQ4cbgA5AAAJAAEJAABtLAAAAAAAAA==.Taediris:BAAALgADCgkJCQAAAA==.Taeolen:BAAALgADCgYJBgABLgAECgkJJwAhANoaAA==.Takova:BAAALgAECgIJAgAAAA==.Tanao:BAABLgAECn8bAAMIAAcJ0wgAfAAEAQAIAAcJlwcAfAAEAQAJAAMJagdCGAB/AAAAAA==.Tarisama:BAAALgAECgUJBQAAAA==.Tasalia:BAAALgADCgIJAgABLgAFFAUJHQANAC0eAA==.Taurox:BAAALgAECgQJBgAAAA==.',
Te='Tegriddy:BAAALgAECgEJAgAAAA==.Teholyone:BAABLgAECn8VAAISAAgJHxEgVwB8AQASAAgJHxEgVwB8AQAAAA==.Tenshe:BAAALgADCgIJAgAAAA==.Tenshi:BAAALgAECgQJBAAAAA==.Terravesh:BAABLgAECn8ZAAMcAAcJ5SCMBQB2AgAcAAcJ5SCMBQB2AgAbAAUJ4Rn1LgAkAQABLgAECgkJJgAKAEIdAA==.Tessia:BAAALgADCgYJCgAAAA==.',
Th='Theselin:BAAALgADCgMJAwABLgAECgkJKAARAG0bAA==.Thog:BAAALgADCgEJAQABLgAFFAQJBgAGAGoRAA==.Thundergunt:BAAALgAECgUJCgABLgAFFAMJBwARAPkjAA==.',
Ti='Tianjin:BAAALgADCgIJAgAAAA==.Ticklebunny:BAAALgAECgEJAQAAAA==.Timid:BAAALgAECgcJEgAAAA==.Timidiot:BAABLgAECn8aAAINAAgJEg8KUgCGAQANAAgJEg8KUgCGAQAAAA==.Tintaglia:BAABLgAECn8xAAISAAgJOQ+KWQB2AQASAAgJOQ+KWQB2AQAAAA==.Tipsydoodles:BAABLgAECn8uAAMKAAkJPRYMDwBKAgAKAAkJPRYMDwBKAgAhAAEJ8gdueQAsAAAAAA==.Tiratore:BAAALgAECgcJCgAAAA==.',
To='Toaster:BAABLgAECn8iAAMoAAkJPQvyAgClAQAoAAkJPQvyAgClAQAXAAIJdghrDABhAAAAAA==.Toni:BAAALgADCgkJIgAAAA==.Tonylazuto:BAAALgADCgQJAQAAAA==.Toodles:BAAALgAECgYJBgAAAA==.Toranaar:BAAALgADCgMJAwAAAA==.Toruk:BAABLgAECn8cAAIIAAgJhxrrNADFAQAIAAgJhxrrNADFAQAAAA==.',
Tr='Trigger:BAAALgADCgcJDAAAAA==.Triggers:BAAALgADCgIJAgAAAA==.Triptan:BAAALgAECgQJBAAAAA==.Trust:BAABLgAECn8kAAIQAAgJkxZdMQDEAQAQAAgJkxZdMQDEAQAAAA==.',
Tu='Tunawhale:BAABLgAECn8sAAMBAAgJ7BSQDgCwAQABAAgJ7BSQDgCwAQAfAAgJ4QUyIQD4AAAAAA==.',
Ty='Tyloriavis:BAAALgAECgYJEAAAAA==.Tyrie:BAAALgADCgYJBwAAAA==.Tyríon:BAAALgADCgkJEgAAAA==.',
['Tù']='Tùsk:BAAALgAECgcJEwAAAA==.',
Ul='Ulfberht:BAAALgADCgMJAwAAAA==.',
Un='Uncletouchie:BAABLgAECn8oAAMMAAgJGg/dHwByAQAMAAgJGg/dHwByAQAWAAUJ3xHhMAD/AAAAAA==.',
Us='Ushira:BAAALgAECgYJBgAAAA==.',
Va='Vados:BAAALgADCgUJBgAAAA==.Vaeliir:BAAALgAECgYJDQAAAA==.Valhart:BAABLgAECn83AAIGAAgJxCGeCgB1AgAGAAgJxCGeCgB1AgAAAA==.Vampt:BAAALgAECgEJAgAAAA==.Vandsong:BAAALgAECgYJDwAAAA==.Vasukin:BAABLgAECn8eAAILAAgJah8wKgAvAgALAAgJah8wKgAvAgAAAA==.',
Ve='Veloura:BAAALgAECgUJCgAAAA==.Velyndine:BAAALgAECgMJAwAAAA==.Veneration:BAAALgAECgUJBgAAAA==.Vesani:BAAALgAECgQJBAAAAA==.',
Vi='Vinsama:BAAALgAECgYJDAAAAA==.Vinsamo:BAAALgADCgYJBgAAAA==.Violentjudge:BAAALgAECggJDgAAAA==.Virgocelest:BAAALgAECgcJDwAAAA==.Viridion:BAACLgAFFH8HAAIcAAQJfBOCEAApAQAcAAQJfBOCEAApAQAuAAQKfzEAAhwACAnuI+YBACwDABwACAnuI+YBACwDAAAA.Virtues:BAABLgAECn8gAAIGAAkJzxUwJwAiAgAGAAkJzxUwJwAiAgAAAA==.',
Vo='Voidblade:BAAALgADCgYJEQAAAA==.Voido:BAAALgADCggJEgABLgAECgkJOwAKACQgAA==.Vonmack:BAAALgADCgYJDwAAAA==.Vorlos:BAAALgAECgMJAwAAAA==.Vorquin:BAACLgAFFH8VAAMNAAUJ9xgVNwBGAQANAAQJ9xgVNwBGAQAFAAEJAACePQAAAAAuAAQKfxYAAw0ACAmoHfhIABgCAA0ACAmoHfhIABgCAAUAAQlKFKZBADsAAAAA.',
Vr='Vreeg:BAABLgAECn8xAAIJAAgJ4RssBAD4AQAJAAgJ4RssBAD4AQAAAA==.',
Vt='Vtec:BAABLgAECn8WAAIjAAgJRwx7NACGAQAjAAgJRwx7NACGAQAAAA==.',
Vy='Vynayro:BAAALgAECgYJCQAAAA==.Vynhalla:BAAALgAECgYJBgAAAA==.',
['Vö']='Vörðr:BAAALgADCgMJBAAAAA==.',
Wa='Wargodx:BAAALgADCgUJBQAAAA==.',
We='Weep:BAAALgADCgQJBAABLgAECgkJCwATAAAAAA==.',
Wh='Whatthehelly:BAABLgAECn8iAAQVAAgJSRPvJQDOAQAVAAgJSRPvJQDOAQAlAAYJnQHfJwBfAAAUAAEJiQUjxwAdAAAAAA==.Whoopycushin:BAAALgAECgIJBgAAAA==.Whyamialive:BAACLgAFFH8bAAIFAAYJbCKFAgABAgAFAAYJbCKFAgABAgAuAAQKfzsAAgUACQlFJoAAAGIDAAUACQlFJoAAAGIDAAAA.',
Wi='Wide:BAAALgADCgYJDAAAAA==.Wiffles:BAAALgAFFAIJAgABLgAFFAYJGQANAGseAA==.Willowes:BAEALgADCgIJAgABLgAFFAUJEwAWAKwXAA==.Willowest:BAECLgAFFH8KAAIeAAUJ+xHJEQBjAQAeAAUJ+xHJEQBjAQAuAAQKfxoAAh4ACAmlGK4XADgCAB4ACAmlGK4XADgCAAEuAAUUBQkTABYArBcA.Willowing:BAEBLgAECn8UAAQIAAcJEBXeWwBMAQAIAAcJuRDeWwBMAQAJAAMJHRlgHQCGAAAHAAIJpxdsKwBAAAABLgAFFAUJEwAWAKwXAA==.Willowish:BAECLgAFFH8TAAIWAAUJrBclCABpAQAWAAUJrBclCABpAQAuAAQKfykAAhYACQnYID0BAHMDABYACQnYID0BAHMDAAAA.Willowly:BAEALgAECgUJCwABLgAFFAUJEwAWAKwXAA==.Winnhao:BAAALgADCgEJAQABLgAECgkJLQAbAAoZAA==.Wiskii:BAABLgAECn8tAAIZAAgJth87CAD7AQAZAAgJth87CAD7AQAAAA==.Wizerds:BAAALgAECgEJAgABLgAECgcJDwATAAAAAA==.',
Wo='Wormwort:BAAALgAECgcJEwAAAA==.',
Wu='Wukon:BAAALgAECgEJAgAAAA==.',
Wy='Wytnarthom:BAABLgAECn8eAAMGAAcJKBtMHwClAQAGAAcJShlMHwClAQABAAYJZhkAGgB/AQABLgAECggJMwAhAC0ZAA==.Wytohne:BAABLgAECn8zAAMhAAgJLRmPEgDcAQAhAAgJIBmPEgDcAQAaAAYJvxEbLAAdAQAAAA==.Wytvori:BAAALgADCgYJBgABLgAECggJMwAhAC0ZAA==.',
['Wæ']='Wærlõga:BAAALgADCgEJAQAAAA==.',
['Wý']='Wýnn:BAAALgADCgYJCQAAAA==.',
Xa='Xanrawr:BAAALgADCgUJBQAAAA==.Xanthiana:BAAALgADCgcJBgAAAA==.Xaree:BAABLgAECn8xAAMKAAgJwh4JCQCrAgAKAAgJwh4JCQCrAgAhAAIJah6lYQCJAAAAAA==.',
Xc='Xcat:BAACLgAFFH8OAAISAAUJQgpaFABrAQASAAUJQgpaFABrAQAuAAQKfx4AAhIACQlFG40jAJoCABIACQlFG40jAJoCAAAA.',
Xd='Xdog:BAAALgADCgYJDQAAAA==.Xdrake:BAABLgAECn8jAAMbAAgJDBnLFADpAQAbAAgJDBnLFADpAQAdAAMJuwIUNwBfAAAAAA==.',
Ya='Yarnad:BAAALgADCgEJAQAAAA==.',
Yi='Yim:BAABLgAECn8fAAISAAcJbiIUIQA+AgASAAcJbiIUIQA+AgAAAA==.Yirtkalii:BAAALgADCgkJHQAAAA==.Yismypetdead:BAAALgAECgEJAQABLgAECgQJCwATAAAAAA==.',
Yl='Ylifiz:BAAALgAECgEJAQAAAA==.',
Yo='Yorshka:BAABLgAECn8oAAIWAAkJdxqGCgClAgAWAAkJdxqGCgClAgAAAA==.',
Yu='Yumiella:BAAALgADCgcJBwAAAA==.',
Za='Zaelthar:BAAALgAECgYJDQAAAA==.Zarilla:BAAALgAECgYJBgABLgAECgcJDgATAAAAAA==.Zatrekas:BAABLgAECn8XAAIJAAcJ+RqvBwCHAQAJAAcJ+RqvBwCHAQAAAA==.',
Ze='Zee:BAABLgAECn84AAIZAAkJ8hA0DwB4AQAZAAkJ8hA0DwB4AQAAAA==.Zeff:BAABLgAECn8tAAIUAAgJNBHiMwCFAQAUAAgJNBHiMwCFAQAAAA==.Zeldris:BAAALgADCgEJAQAAAA==.Zephuros:BAABLgAECn8nAAMcAAgJvRqsBwA1AgAcAAgJvRqsBwA1AgAbAAEJRgbNZwAmAAAAAA==.',
Zi='Ziunepaws:BAAALgAECgcJEwAAAA==.',
Zo='Zoldyck:BAAALgAFFAIJAgABLgAFFAMJAwATAAAAAA==.Zompt:BAAALgAECgMJAwAAAA==.Zorionsson:BAAALgADCgEJAQAAAA==.',
Zw='Zwaard:BAAALgAECgEJAQAAAA==.',
Zy='Zyasa:BAABLgAECn8xAAMYAAkJ8BwwDQBEAgAYAAgJhhgwDQBEAgAWAAYJwRjzGwCdAQAAAA==.Zymar:BAAALgAECgIJBwABLgAECggJHQAlAIQeAA==.',
['År']='Årfårf:BAAALgAECgIJAgAAAA==.',
['Æl']='Ælgernon:BAAALgAECgYJCwAAAA==.',
['Æz']='Æzio:BAAALgADCgYJCQAAAA==.',
['Ðæ']='Ðæmôn:BAAALgADCgEJAQABLgAECgYJHgAYAAEeAA==.',
['Ðé']='Ðéxx:BAAALgAECgEJAQAAAA==.',
['ßa']='ßarackoshama:BAAALgAECgQJBQAAAA==.',
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
