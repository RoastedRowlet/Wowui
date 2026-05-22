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

local lookup = {'Warrior-Fury','Rogue-Subtlety','Mage-Frost','Hunter-Survival','Warrior-Protection','Priest-Discipline','Druid-Restoration','Monk-Mistweaver','DeathKnight-Blood','DeathKnight-Unholy','Unknown-Unknown','Druid-Balance','Paladin-Retribution','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Paladin-Holy','Priest-Shadow','Monk-Brewmaster','Shaman-Restoration','Monk-Windwalker','Warlock-Destruction','Druid-Guardian','Shaman-Elemental','DeathKnight-Frost','DemonHunter-Vengeance','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Priest-Holy','DemonHunter-Devourer','Rogue-Assassination','Rogue-Outlaw','Hunter-Marksmanship','Shaman-Enhancement','Druid-Feral','Warrior-Arms','DemonHunter-Havoc','Mage-Fire',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=46,date='2026-05-16',data={Ac='Acharon:BAABLgAECn8sAAIBAAkJABj4DgA9AgABAAkJABj4DgA9AgAAAA==.',
Ad='Adrastus:BAAALgAECgYJDgAAAA==.',
Ae='Aeslin:BAAALgAECgYJEgAAAA==.',
Af='Af:BAAALgAECgQJBAABLgAFFAMJBgACAOcdAA==.',
Ah='Ahsoka:BAAALgAECgYJDgAAAA==.',
Ai='Ain:BAAALgAFFAEJAQAAAA==.Ainslie:BAAALgAECgYJCQAAAA==.',
Al='Alarashinu:BAABLgAECn8eAAIDAAcJ6wTDsADkAAADAAcJ6wTDsADkAAAAAA==.Alataris:BAAALgADCgUJCgAAAA==.Alawae:BAABLgAECn8mAAIEAAkJ4x8pBwB1AgAEAAkJ4x8pBwB1AgAAAA==.Altria:BAAALgADCgcJEAAAAA==.',
Am='Amarco:BAABLgAECn8WAAIFAAgJhxZ2EQCBAQAFAAgJhxZ2EQCBAQAAAA==.',
An='Anahit:BAAALgAECgEJAQAAAA==.Angela:BAAALgADCgcJEAABLgAECgkJLQAGALsWAA==.Anosvoldgoad:BAAALgAECgIJAQAAAA==.',
Ap='Apaka:BAAALgADCgEJAQAAAA==.',
Ar='Araedia:BAAALgAECgYJCAABLgAECgkJIAAHAC8UAA==.Arahant:BAACLgAFFH8RAAIIAAQJihgoFQAhAQAIAAQJihgoFQAhAQAuAAQKfzIAAggACQkJHgENAIMCAAgACQkJHgENAIMCAAAA.Arazat:BAAALgADCgIJAgAAAA==.Aretas:BAABLgAECn8qAAMJAAkJiCHMAgDqAgAJAAkJiCHMAgDqAgAKAAEJsxYLDQE3AAAAAA==.Arriånna:BAAALgADCgkJFAAAAA==.Arrowpeen:BAAALgAECgQJBwAAAA==.',
As='Ashuffle:BAAALgAECgQJCwAAAA==.Asifa:BAABLgAECn8VAAIDAAYJmBSGeQBHAQADAAYJmBSGeQBHAQAAAA==.Astinds:BAAALgADCgMJBQABLgAECgUJCAALAAAAAA==.',
At='Atherion:BAABLgAECn8pAAIDAAgJ6xOKSwC1AQADAAgJ6xOKSwC1AQAAAA==.',
Au='Aurod:BAAALgADCgMJBAAAAA==.',
Av='Avareh:BAAALgADCgIJAQAAAA==.Averix:BAAALgAECgEJAwABLgAECgcJEQALAAAAAA==.Avranarada:BAABLgAECn8gAAMHAAkJLxSrGwAgAgAHAAkJLxSrGwAgAgAMAAQJtBC0RgCbAAAAAA==.',
Az='Azung:BAABLgAECn8rAAINAAkJbh8oIwCcAgANAAkJbh8oIwCcAgAAAA==.',
Ba='Babaisyaga:BAACLgAFFH8VAAIOAAQJqhmYCgANAQAOAAQJqhmYCgANAQAuAAQKfzQAAg4ACQnjI54CAD8DAA4ACQnjI54CAD8DAAAA.Baelia:BAAALgAECgEJAQAAAA==.Baimes:BAABLgAECn8cAAMPAAkJERHBBQC+AQAPAAkJERHBBQC+AQAQAAEJXwFrNAEUAAAAAA==.Baka:BAABLgAECn81AAMRAAgJVyXCAgBJAwARAAgJVyXCAgBJAwANAAYJNBChkQBZAQAAAA==.Balance:BAAALgADCgIJAgAAAA==.Balinse:BAABLgAECn8XAAIFAAgJyBnlCgDzAQAFAAgJyBnlCgDzAQAAAA==.Bandruì:BAAALgAECgMJAwAAAA==.Bankpoo:BAACLgAFFH8RAAIKAAQJ4BgqLwBUAQAKAAQJ4BgqLwBUAQAuAAQKfycAAwoACAmzH9oeAEsCAAoABwmXI9oeAEsCAAkAAQlXCMtFACwAAAAA.Baragohn:BAAALgADCggJCAAAAA==.Barb:BAAALgAECgIJAgAAAA==.Barrelrollin:BAAALgAECgYJDAAAAA==.Batrito:BAABLgAECn8tAAMGAAkJuxYPDQBHAgAGAAkJuxYPDQBHAgASAAcJuRQ6HwB3AQAAAA==.Bawchu:BAAALgADCgcJBwAAAA==.',
Be='Bealzebubbà:BAABLgAECn8WAAIOAAcJrQnnWgA4AQAOAAcJrQnnWgA4AQAAAA==.Bearlylegál:BAAALgAFFAEJAQABLgAFFAMJBQATAJwfAA==.Beastfodays:BAAALgAECgcJEgAAAA==.Beaviss:BAAALgADCgUJBQAAAA==.Benn:BAABLgAECn8VAAMRAAYJ1hXDMgCzAQARAAYJ1hXDMgCzAQANAAYJGAi/oADpAAAAAA==.Bethlahammer:BAAALgAECgQJCAABLgAECgYJCAALAAAAAA==.',
Bi='Bigboom:BAAALgAECgEJAQAAAA==.Billcosbrew:BAACLgAFFH8FAAITAAMJnB8KGQAZAQATAAMJnB8KGQAZAQAuAAQKfyMAAhMACAkHJhYEAEsDABMACAkHJhYEAEsDAAAA.Biomechan:BAAALgAECgQJDQAAAA==.',
Bj='Bjorinn:BAAALgAECgIJAgAAAA==.',
Bl='Blackleaf:BAAALgAECgQJCwAAAA==.Blankshot:BAAALgADCgMJAwAAAA==.Blightsides:BAAALgAECgMJAwABLgAECggJGQAUAFwPAA==.Blizzcon:BAABLgAECn82AAMGAAgJ6RWjEQACAgAGAAgJ6RWjEQACAgASAAQJEQgBQAC3AAAAAA==.',
Bo='Borrgar:BAABLgAECn8dAAINAAYJlSDPSQCgAQANAAYJlSDPSQCgAQAAAA==.',
Br='Brackle:BAABLgAECn8qAAIOAAgJqCCjFQBcAgAOAAgJqCCjFQBcAgAAAA==.Bracori:BAACLgAFFH8PAAIIAAQJ4BiaFAAnAQAIAAQJ4BiaFAAnAQAuAAQKfywAAwgACQmnEA8oAHQBAAgACQmnEA8oAHQBABUABwnPE0ckADsBAAAA.Brandywynne:BAABLgAECn8pAAIOAAkJvg07PQCWAQAOAAkJvg07PQCWAQAAAA==.Brick:BAABLgAECn8yAAICAAkJ6CNHAQA4AwACAAkJ6CNHAQA4AwAAAA==.Briggsie:BAAALgADCgQJBgAAAA==.Briggsy:BAAALgAECgEJAQAAAA==.Brightfame:BAACLgAFFH8FAAMPAAIJwhJbBgCdAAAPAAIJZxBbBgCdAAAWAAEJgRdjFgBSAAAuAAQKfzcAAxYACAnPHlgEAO0BABYACAnRGVgEAO0BAA8ABwnkHx4FANMBAAAA.Bronny:BAAALgADCgMJAwAAAA==.Brownpepperz:BAAALgADCgEJAQAAAA==.Bruticus:BAAALgADCggJCAAAAA==.',
Bu='Bubblebull:BAAALgAECgEJAQAAAA==.Buffalox:BAAALgADCgUJBQAAAA==.Buffshagwell:BAAALgAECgUJCgAAAA==.Butterbllz:BAACLgAFFH8FAAINAAMJHxbpTwCtAAANAAMJHxbpTwCtAAAuAAQKfxkAAg0ACQnqGQJoAK8BAA0ACQnqGQJoAK8BAAAA.',
Ca='Caius:BAAALgADCgUJDAAAAA==.Calaine:BAAALgADCgcJBwAAAA==.Calypsio:BAABLgAECn8hAAINAAYJEBPteAAwAQANAAYJEBPteAAwAQAAAA==.Camany:BAABLgAECn8ZAAIOAAgJjRR1MgDAAQAOAAgJjRR1MgDAAQAAAA==.Cantread:BAAALgAECgcJBwABLgAFFAQJDAASAJcNAA==.Caralath:BAAALgAECgMJAwAAAA==.Caramaulize:BAAALgAECgQJBAAAAA==.Caretakerz:BAABLgAECn8cAAIXAAcJ8RpfCwDBAQAXAAcJ8RpfCwDBAQAAAA==.Cartus:BAABLgAECn8lAAMYAAcJzgxiOQD4AAAYAAcJzgxiOQD4AAAUAAUJRQW5dACIAAAAAA==.',
Ce='Cedre:BAAALgADCgYJEgAAAA==.Celidoria:BAABLgAECn8aAAINAAgJ0B9GKwB2AgANAAgJ0B9GKwB2AgAAAA==.',
Ch='Chainfrost:BAAALgADCgEJAQAAAA==.Cheesepuff:BAABLgAECn8ZAAIQAAYJkwnmkADbAAAQAAYJkwnmkADbAAAAAA==.Chikara:BAAALgAECgQJBgAAAA==.Chittypalli:BAAALgADCgcJBwAAAA==.',
Ci='Cindera:BAAALgAECgMJAwABLgAFFAQJEwADAPQXAA==.Cinnibar:BAAALgADCgYJBgAAAA==.Cirï:BAAALgAECgYJDAAAAA==.Cisbick:BAABLgAECn8WAAIQAAYJFg3rngAbAQAQAAYJFg3rngAbAQAAAA==.',
Cl='Clamshell:BAABLgAECn8qAAMKAAkJxiNUCAD7AgAKAAkJxiNUCAD7AgAZAAEJAAAyKAAAAAAAAA==.Clayier:BAAALgAECgQJCQAAAA==.',
Cn='Cntendr:BAAALgAECgMJBQAAAA==.Cntendrthree:BAAALgADCgMJAwAAAA==.',
Co='Codenike:BAABLgAECn8cAAMVAAgJnh2VCwA+AgAVAAgJnh2VCwA+AgAIAAQJCg+XSACsAAAAAA==.Companionbea:BAAALgAECgQJBwAAAA==.Consume:BAAALgADCgQJBAABLgAECggJIAANAJMiAA==.Corbanite:BAAALgAECgQJCQAAAA==.Corelheals:BAAALgADCgMJAwAAAA==.Corpsè:BAAALgAECgYJDgAAAA==.Covertyqt:BAABLgAECn8sAAIDAAkJnCGPCwDtAgADAAkJnCGPCwDtAgAAAA==.Coyote:BAAALgAECgkJAgAAAA==.',
Cp='Cptnhuman:BAABLgAECn8sAAIKAAkJlBeOKwALAgAKAAkJlBeOKwALAgAAAA==.',
Cr='Crunk:BAAALgAECgQJCAAAAA==.Cryptis:BAAALgADCgEJAQAAAA==.',
['Cõ']='Cõrpses:BAEALgAECgQJBAABLgAECgIJAgALAAAAAA==.',
Da='Daboof:BAAALgAECgEJAQAAAA==.Daddydragon:BAAALgADCgYJCgAAAA==.Daemandred:BAAALgADCggJCgAAAA==.Daggere:BAAALgAECgEJBAAAAA==.Damaged:BAAALgAECgQJBAAAAA==.Damian:BAAALgAECgUJBwABLgAECgYJCgALAAAAAA==.Danfu:BAAALgADCgEJAQAAAA==.Danke:BAAALgAECgYJEQAAAA==.Dankrazor:BAAALgADCggJDAAAAA==.Dankz:BAAALgADCgEJAQAAAA==.Darckinz:BAAALgAECgYJEgAAAA==.Darkenmicky:BAABLgAECn8eAAITAAcJoQ0xKgAnAQATAAcJoQ0xKgAnAQAAAA==.Darkmickyz:BAAALgAECgQJBgAAAA==.Darkqueenx:BAAALgADCgIJAgAAAA==.Darksev:BAAALgADCgIJAgAAAA==.Darthbobula:BAACLgAFFH8RAAINAAQJWwkDLgAfAQANAAQJWwkDLgAfAQAuAAQKfywAAg0ACQlqH5MUAIsCAA0ACQlqH5MUAIsCAAAA.Darthceril:BAAALgAECgUJBgAAAA==.Daswar:BAAALgAFFAEJAQAAAA==.Dayloc:BAABLgAECn8sAAIQAAkJdw+yOAC3AQAQAAkJdw+yOAC3AQAAAA==.',
De='Deataria:BAAALgAECgUJBQAAAA==.Deathrho:BAAALgADCgkJFQAAAA==.Deathwish:BAAALgAECgIJAgAAAA==.Delryth:BAAALgAECgQJBwAAAA==.Delyne:BAAALgADCgYJCAAAAA==.Demonatrix:BAAALgADCgEJAQAAAA==.Demontyk:BAAALgADCgkJEAAAAA==.Denareas:BAAALgAECgYJCgAAAA==.Detox:BAAALgADCgQJBAAAAA==.',
Di='Diablõ:BAEBLgAECn8mAAIaAAkJYhz+AgBwAgAaAAkJYhz+AgBwAgABLgAECgIJAgALAAAAAA==.Dirtyd:BAAALgAECgQJBwAAAA==.Dirtydeeds:BAABLgAECn8nAAIKAAkJfhDINgDeAQAKAAkJfhDINgDeAQAAAA==.Divinetism:BAAALgAECgcJDgAAAA==.',
Dl='Dl:BAABLgAECn87AAISAAkJgh96BQDFAgASAAkJgh96BQDFAgAAAA==.',
Dr='Draccarys:BAAALgAECgcJCAAAAA==.Draekbee:BAABLgAECn8kAAQbAAgJGxWZFACfAQAcAAgJmBHmHwDCAQAbAAYJZBiZFACfAQAdAAEJwwdpSgAtAAAAAA==.Dragkohn:BAAALgAECgYJBgABLgAECgkJHwARAGwlAA==.Dragonaged:BAAALgADCgMJAwAAAA==.Drakkarr:BAAALgADCgcJCwAAAA==.Drannek:BAAALgAECgEJAgAAAA==.Drimbirt:BAAALgAECgQJCAAAAA==.Drinkmormilk:BAAALgAECgYJEAAAAA==.Drogman:BAAALgAECgEJAQAAAA==.Droowin:BAAALgAECgIJAgABLgAECgYJDAALAAAAAA==.Drshockaloo:BAAALgADCgYJCgAAAA==.',
Du='Duvori:BAAALgAECgEJAQAAAA==.',
Dy='Dyspepsia:BAAALgADCgMJCAAAAA==.',
Eb='Ebullition:BAABLgAECn8ZAAIOAAgJyRbLLADYAQAOAAgJyRbLLADYAQAAAA==.',
Ed='Edensfury:BAAALgAECgYJCAAAAA==.',
Ei='Eightyhd:BAAALgADCgkJCQAAAA==.Eigi:BAAALgAECggJEAAAAA==.',
Ek='Ekthelion:BAABLgAECn8lAAIeAAcJshnVCwCyAQAeAAcJshnVCwCyAQAAAA==.',
El='Elavelin:BAAALgADCgUJCgAAAA==.Eldanon:BAABLgAECn8YAAIWAAYJaiA1CgAbAgAWAAYJaiA1CgAbAgAAAA==.Eleyert:BAABLgAECn8pAAIYAAkJlCT1AQA1AwAYAAkJlCT1AQA1AwAAAA==.Elwe:BAABLgAECn8VAAIfAAgJ2iCNBwCxAgAfAAgJ2iCNBwCxAgAAAA==.',
Em='Emmaga:BAABLgAECn8WAAIDAAYJmxBPigAoAQADAAYJmxBPigAoAQAAAA==.Emrhakul:BAAALgADCgEJAQAAAA==.',
En='Enkidu:BAABLgAECn8gAAIOAAYJQBxKLgD5AQAOAAYJQBxKLgD5AQAAAA==.Enseth:BAABLgAECn8iAAQcAAgJZxIWIQB/AQAcAAgJZxIWIQB/AQAbAAQJNQfjLQCsAAAdAAIJpAYPQwBVAAAAAA==.',
Er='Erotikzombie:BAABLgAECn8VAAIKAAYJcB5cTgCQAQAKAAYJcB5cTgCQAQAAAA==.Errilyn:BAAALgADCgYJBgAAAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Eu='Eulogy:BAAALgAECgYJEgABLgAECggJNgAGAOkVAA==.',
Ex='Exene:BAABLgAECn8UAAMgAAkJ1wtqVwAvAQAgAAkJMwdqVwAvAQAaAAQJthFAGwC3AAAAAA==.',
Fa='Faelwen:BAAALgAECgIJAgAAAA==.Fairious:BAABLgAECn8qAAMCAAgJuRz8CwAYAgACAAgJcRz8CwAYAgAhAAcJchCzCQBbAQAAAA==.Fangrell:BAAALgADCgEJAgABLgAECgkJKQAOAIEWAA==.Faror:BAAALgAECgEJAQAAAA==.',
Fe='Feethunter:BAAALgAECgEJAQABLgAFFAcJHQACAJIWAA==.Felcon:BAAALgAECgEJAgAAAA==.Fellivath:BAAALgAECgYJBwAAAA==.Fenrirr:BAAALgADCgYJBgABLgAECgYJHQANAJUgAA==.Fet:BAACLgAFFH8dAAMCAAcJkhYPAgDlAQACAAcJfhUPAgDlAQAiAAQJZw6MAwAwAQAuAAQKfywAAwIACQl2JNwIAAMDAAIACQl2JNwIAAMDACIABgmjIZUFALgBAAAA.Feyu:BAEALgAECgYJCQABLgAECggJGAAUAD4ZAA==.',
Fh='Fhatbashtud:BAAALgAECgIJAgAAAA==.',
Fi='Fireflies:BAAALgAFFAMJAwAAAA==.Firelore:BAAALgAECgcJAwABLgAFFAEJAQALAAAAAA==.Fistsoiaaryn:BAAALgAECgYJBwAAAA==.',
Fl='Flatline:BAABLgAECn8WAAIGAAgJwRM4EwDvAQAGAAgJwRM4EwDvAQAAAA==.Flattymatty:BAAALgADCgYJBgAAAA==.Flöti:BAEBLgAECn8YAAIUAAgJPhkhHQAxAgAUAAgJPhkhHQAxAgAAAA==.',
Fo='Four:BAABLgAECn8gAAINAAgJjhFWWQB2AQANAAgJjhFWWQB2AQAAAA==.',
Fr='Frayla:BAAALgADCgMJAwAAAA==.Frostnips:BAABLgAECn8UAAIDAAcJ9h4gOQDzAQADAAcJ9h4gOQDzAQAAAA==.Frysky:BAABLgAECn8UAAIXAAYJ+Q2AGQDkAAAXAAYJ+Q2AGQDkAAAAAA==.',
Fu='Furytotem:BAAALgADCgMJAwABLgAECgUJBwALAAAAAA==.Futz:BAABLgAECn8nAAIRAAgJSCTyAwAmAwARAAgJSCTyAwAmAwAAAA==.Fuzzymage:BAAALgAECgEJAwAAAA==.',
Ga='Gadrolicus:BAAALgADCgEJAQAAAA==.Galadriell:BAABLgAECn8fAAMOAAgJphtXMwC8AQAOAAgJphtXMwC8AQAjAAYJmQ9UQwBKAQAAAA==.Gargahmell:BAAALgADCgUJBQAAAA==.',
Ge='Gengarr:BAAALgAECgMJAgAAAA==.',
Gn='Gnomes:BAAALgADCgcJBwAAAA==.',
Go='Goobermanic:BAAALgAECgQJCAAAAA==.Gooberz:BAAALgADCgYJBgAAAA==.Goobs:BAAALgADCgcJDwAAAA==.Goonxoxo:BAAALgADCgUJCAAAAA==.Gordoe:BAAALgAECgEJAQAAAA==.Gothberry:BAAALgADCgUJBgAAAA==.',
Gp='Gpa:BAAALgADCgEJAQAAAA==.',
Gr='Graveborne:BAAALgADCgkJGwAAAA==.Gravess:BAABLgAECn8tAAMiAAkJXxu8AgBEAgAiAAkJXxu8AgBEAgAhAAIJUxRgFQCEAAAAAA==.Gravewin:BAAALgADCgMJBQABLgAECgYJDAALAAAAAA==.Grendelheim:BAAALgAECgEJAQAAAA==.Grogar:BAAALgADCgMJAwAAAA==.',
Gu='Gurg:BAAALgAECgYJCwAAAA==.',
Gw='Gwynath:BAABLgAECn8fAAMfAAgJriOfAwAcAwAfAAgJriOfAwAcAwAGAAYJtxpKIQBlAQAAAA==.',
Ha='Hagrok:BAAALgADCgEJAQAAAA==.Haldael:BAAALgAECgQJBAAAAA==.Hammerfists:BAAALgAECgQJCQAAAA==.Hanbil:BAAALgAECgYJDQAAAA==.Handace:BAAALgAECgUJBQAAAA==.Hangezoe:BAAALgAECgQJBQABLgAECggJFgAFAIcWAA==.Hantak:BAAALgAECgQJCgAAAA==.Hathaendron:BAAALgADCgMJAwAAAA==.Hatsunemiku:BAAALgADCgcJDQAAAA==.Hawginmaw:BAAALgADCgMJAwAAAA==.',
He='Hemorrhagic:BAAALgADCgIJAgAAAA==.Heph:BAAALgADCgcJBwABLgADCggJGAALAAAAAA==.Heretic:BAAALgAECgQJBAAAAA==.',
Hi='Hiromi:BAABLgAECn8mAAIFAAgJjRNtFgBAAQAFAAgJjRNtFgBAAQAAAA==.',
Ho='Hoisin:BAABLgAECn8bAAITAAgJ2RWDHgB0AQATAAgJ2RWDHgB0AQABLgAECgkJCQALAAAAAA==.Holyyballs:BAABLgAECn8YAAIRAAgJRB24DAB6AgARAAgJRB24DAB6AgAAAA==.Hotrodbob:BAAALgAECgEJAgAAAA==.Hotshot:BAAALgADCgQJAwAAAA==.Howlymandel:BAAALgAECgkJAwABLgAECgkJKQAOAIEWAA==.Hoytx:BAAALgAECgQJBAAAAA==.',
Hu='Huntstokill:BAAALgAECgMJBAAAAA==.Huskerfister:BAABLgAECn8vAAIVAAkJtiLJAwDqAgAVAAkJtiLJAwDqAgAAAA==.Hussion:BAAALgADCgMJBQAAAA==.',
['Hì']='Hìroko:BAABLgAECn8XAAIQAAYJogSanwC+AAAQAAYJogSanwC+AAAAAA==.',
Ia='Iaaryn:BAAALgAECgQJBAAAAA==.',
Ic='Icedemon:BAAALgAECgEJAgAAAA==.Icey:BAAALgADCgEJAgAAAA==.Ichigò:BAAALgAECgEJAQAAAA==.',
Il='Illiderp:BAAALgAECgQJCAABLgAECgQJDQALAAAAAA==.',
Im='Imananji:BAAALgAECgMJBAABLgAFFAQJEQAXAJEQAA==.Imasurvivor:BAAALgADCgYJBgAAAA==.Imblind:BAABLgAECn8eAAIgAAkJxh2SGABBAgAgAAkJxh2SGABBAgAAAA==.Imperius:BAAALgAECgEJAQABLgAECgYJEgALAAAAAA==.',
In='Infernodruid:BAAALgAECgMJBQABLgAECgUJBwALAAAAAA==.Infinitie:BAAALgAECgEJAQAAAA==.Insillico:BAABLgAECn8eAAIDAAcJ1Q74cQBXAQADAAcJ1Q74cQBXAQAAAA==.',
Io='Iog:BAAALgAECgYJCQAAAA==.',
Ip='Iplaydead:BAABLgAECn8gAAIOAAgJDBbBMwC7AQAOAAgJDBbBMwC7AQAAAA==.',
Ir='Iroh:BAABLgAECn8UAAIVAAgJoBz0DgALAgAVAAgJoBz0DgALAgAAAA==.Irondali:BAAALgADCgYJBgAAAA==.',
Is='Ismokeprot:BAAALgAECgQJCQAAAA==.',
Ja='Jainastraza:BAAALgAECgIJAgABLgAECgkJKgAKAMYjAA==.Jakub:BAAALgAECgYJCQAAAA==.Jarinduva:BAAALgADCggJHAAAAA==.Jawnson:BAABLgAECn8sAAMCAAkJEBc9DQADAgACAAkJEBc9DQADAgAhAAIJ8RK8GABqAAAAAA==.',
Je='Jeffo:BAAALgAECgMJBQAAAA==.Jenefer:BAACLgAFFH8TAAMJAAQJmhloDgAfAQAJAAQJmhloDgAfAQAKAAEJRgdRVgBNAAAuAAQKfzEAAgkACQnoITUEALcCAAkACQnoITUEALcCAAAA.Jerzak:BAAALgADCgYJCwAAAA==.',
Jo='Joemomo:BAABLgAECn8XAAIBAAgJ0A57KABpAQABAAgJ0A57KABpAQAAAA==.Joethebull:BAAALgADCgQJBAAAAA==.Johnbasilone:BAAALgAECgEJAgABLgAECgMJBAALAAAAAA==.Johnmoo:BAAALgADCgIJAgAAAA==.Johnthick:BAAALgADCgcJFAAAAA==.Jokerninja:BAAALgAECgYJCgAAAA==.Jondooss:BAAALgADCgkJEwAAAA==.Jonsholo:BAAALgAECgIJAwAAAA==.Josefina:BAAALgAECgYJCwAAAA==.',
Ju='Jubelum:BAAALgADCgQJBAAAAA==.',
Ka='Kailback:BAAALgAECggJEQAAAA==.Kait:BAABLgAECn8vAAMUAAkJQRxQFgBEAgAUAAkJQRxQFgBEAgAkAAMJ3gdBJACVAAAAAA==.Kakarotto:BAAALgAECgMJAwABLgAECgYJBwALAAAAAA==.Kaladin:BAAALgAECgUJCgAAAA==.Kalathriel:BAAALgADCgcJCgAAAA==.Kalcifur:BAACLgAFFH8SAAIRAAQJ2BbiFAAwAQARAAQJ2BbiFAAwAQAuAAQKfy0AAhEACQk9Fz8VABYCABEACQk9Fz8VABYCAAAA.Kaseofbeer:BAAALgAECgEJAgAAAA==.Kashisht:BAAALgADCgIJAgAAAA==.Kassanovva:BAAALgAECgIJAgABLgAFFAQJEwAJAJoZAA==.Kasstigate:BAAALgAECgYJEAABLgAFFAQJEwAJAJoZAA==.Kastiel:BAAALgAECgcJEgABLgAECggJFwAFAMgZAA==.Kathtel:BAABLgAECn8YAAIDAAgJJAuPcQBXAQADAAgJJAuPcQBXAQAAAA==.Katstrider:BAABLgAECn8mAAIOAAkJrBl8FwBPAgAOAAkJrBl8FwBPAgAAAA==.Kattarea:BAAALgAECgMJAwABLgAECgkJJgAOAKwZAA==.Kavica:BAAALgAECgYJDAABLgAFFAIJBQAHABQaAA==.Kayotic:BAAALgADCgUJBQAAAA==.',
Ke='Kekw:BAAALgAECgUJDAAAAA==.Keldean:BAABLgAECn8eAAIFAAcJ7BvFDgCtAQAFAAcJ7BvFDgCtAQAAAA==.Kelsier:BAAALgADCgYJBgAAAA==.Kenji:BAAALgAECgEJAgAAAA==.Keryka:BAACLgAFFH8MAAIKAAQJcRj0MQBPAQAKAAQJcRj0MQBPAQAuAAQKfyoAAgoACQkHJfAEAC8DAAoACQkHJfAEAC8DAAAA.Keybomb:BAAALgAECgYJBgAAAA==.',
Kh='Khall:BAAALgAFFAEJAQAAAA==.Khere:BAAALgAECgEJAQAAAA==.',
Ki='Kirigiri:BAABLgAECn8aAAMHAAcJ5A0JWADrAAAHAAcJ5A0JWADrAAAXAAEJAABANAAlAAABLgAFFAQJEgARANgWAA==.Kirøs:BAAALgAECgUJBgAAAA==.Kitanâ:BAAALgADCgMJBAAAAA==.Kiwi:BAAALgAECgEJAgAAAA==.',
Kn='Knom:BAAALgAECgcJDAAAAA==.',
Ko='Kohn:BAABLgAECn8fAAIRAAkJbCUMCQDfAgARAAkJbCUMCQDfAgAAAA==.Kona:BAEALgAECgIJAgAAAA==.Kovalo:BAAALgAECgMJBAAAAA==.',
Kp='Kpegz:BAAALgADCgcJBwABLgAECgkJJgANAOseAA==.',
Kr='Krisjian:BAAALgADCgUJBQAAAA==.Kroh:BAACLgAFFH8NAAIlAAUJvRHCAwBWAQAlAAUJvRHCAwBWAQAuAAQKfyAAAiUACQlTIusEAMYCACUACQlTIusEAMYCAAAA.',
Ku='Kungfugriff:BAAALgAECgMJBAAAAA==.',
Ky='Kytana:BAAALgADCgQJBAAAAA==.',
La='Laisidhiel:BAAALgAECgYJEAAAAA==.Lateo:BAABLgAECn83AAICAAkJCRHZEADTAQACAAkJCRHZEADTAQAAAA==.Lawz:BAABLgAECn8iAAQWAAgJbQcxGACpAAAPAAUJtwc1FAC1AAAWAAcJIwYxGACpAAAQAAcJuAPwqwCnAAAAAA==.',
Le='Leafz:BAACLgAFFH8FAAIHAAIJSxqiNACfAAAHAAIJSxqiNACfAAAuAAQKfx4AAwcACAn7FHUmANQBAAcACAn7FHUmANQBAAwAAQmfDWRoADEAAAAA.Leaonissa:BAAALgAECgMJBAAAAA==.Learn:BAAALgADCgYJBgAAAA==.Leleb:BAAALgAECgUJDAAAAA==.Lelianna:BAAALgAECgEJAQAAAA==.Lemonruss:BAACLgAFFH8LAAINAAQJ6gohKwAoAQANAAQJ6gohKwAoAQAuAAQKfyEAAg0ACQkWGGksAHICAA0ACQkWGGksAHICAAAA.Leshafrierne:BAAALgAECgUJCQABLgAECgUJCwALAAAAAA==.Leshen:BAAALgAECgYJCQAAAA==.Lexia:BAABLgAECn8hAAMWAAcJdgXbFgC0AAAWAAcJdgXbFgC0AAAQAAUJhAObtwCPAAAAAA==.',
Li='Lillika:BAAALgAECgEJAQAAAA==.Lilturtz:BAAALgAECgEJAQABLgAECggJIQAVALIiAA==.Linnea:BAAALgAECgMJAwAAAA==.',
Lo='Loabones:BAAALgADCgcJDwAAAA==.Longhorn:BAABLgAECn8cAAINAAcJZA6ZeQAvAQANAAcJZA6ZeQAvAQAAAA==.Loni:BAAALgAECgcJDwAAAA==.Lookitsopz:BAAALgADCgQJBAAAAA==.Lorrenna:BAAALgAECgIJBQAAAA==.Lorrien:BAAALgAECgQJBAAAAA==.Lorré:BAAALgAECgYJBgABLgAECgQJBAALAAAAAA==.Lortpegsalot:BAABLgAECn8mAAINAAkJ6x57GQBrAgANAAkJ6x57GQBrAgAAAA==.Lostcause:BAAALgAECgEJAQAAAA==.Lowy:BAAALgADCgMJBQAAAA==.',
Lu='Lucena:BAABLgAECn8gAAIfAAYJ8CEPFwAjAgAfAAYJ8CEPFwAjAgAAAA==.Lunas:BAAALgAECgMJBAABLgAECgcJDwALAAAAAA==.',
['Lö']='Lörö:BAAALgADCgQJBAAAAA==.',
Ma='Madamkluck:BAABLgAECn8lAAIHAAcJrR1HGwAjAgAHAAcJrR1HGwAjAgAAAA==.Maglubiyet:BAABLgAECn8cAAIkAAcJoBNpDgBXAQAkAAcJoBNpDgBXAQAAAA==.Magoz:BAAALgADCgcJDAAAAA==.Manhole:BAAALgAECgUJCQAAAA==.Markyb:BAABLgAECn8lAAINAAkJXxDkSACjAQANAAkJXxDkSACjAQAAAA==.Masamura:BAACLgAFFH8VAAIDAAUJQR0iKQBkAQADAAUJQR0iKQBkAQAuAAQKfzEAAgMACQk+HzcdAHECAAMACQk+HzcdAHECAAAA.Mattor:BAAALgADCgYJBgABLgAECggJFgAFAIcWAA==.Maureanna:BAABLgAECn87AAIHAAkJJRvpEACGAgAHAAkJJRvpEACGAgAAAA==.Mavralle:BAAALgAECgUJBQAAAA==.',
Me='Medari:BAECLgAFFH8GAAIdAAMJoAdgGACtAAAdAAMJoAdgGACtAAAuAAQKfyQAAh0ACAnTF88HADICAB0ACAnTF88HADICAAAA.Medwyna:BAAALgAECgcJBQAAAA==.Melorm:BAAALgAECgMJBQAAAA==.',
Mi='Minipig:BAAALgAECgIJAgAAAA==.Mirasharu:BAAALgAECgEJAQAAAA==.Mireille:BAAALgADCgkJFwAAAA==.Miseria:BAAALgADCgIJAgAAAA==.Mitsuri:BAABLgAECn8VAAINAAYJiRIKeQAwAQANAAYJiRIKeQAwAQAAAA==.',
Mn='Mnkyman:BAAALgAECgQJBAAAAA==.',
Mo='Mommamoon:BAAALgAECgYJCgABLgAECggJEwALAAAAAA==.Monachier:BAAALgAECgUJCwAAAA==.Moonkin:BAABLgAECn8UAAIHAAYJaxgNLwCeAQAHAAYJaxgNLwCeAQAAAA==.Moonlïght:BAAALgAECggJEwAAAA==.Moonrage:BAAALgADCgcJCwABLgAECggJEwALAAAAAA==.Moose:BAAALgAECgYJEQAAAA==.Morganlefay:BAABLgAECn8pAAIQAAgJewJTqQCsAAAQAAgJewJTqQCsAAAAAA==.Morgona:BAAALgADCgEJAQAAAA==.Morlyn:BAABLgAECn8YAAIDAAgJOgy0cwBTAQADAAgJOgy0cwBTAQAAAA==.Mosho:BAAALgAECgEJAQABLgAFFAcJHQACAJIWAA==.Mousemist:BAABLgAECn8qAAMVAAkJtht1DwADAgAVAAgJ1xp1DwADAgAIAAcJhAVvTACkAAAAAA==.',
Mu='Mulangar:BAAALgADCgEJAQAAAA==.',
My='Mynameiskase:BAAALgAECgYJEQAAAA==.Mystìc:BAAALgAECgQJCwAAAA==.',
['Má']='Májorrobot:BAAALgAECggJEAAAAA==.',
['Mä']='Mänjo:BAAALgAECgcJDwAAAA==.',
['Mí']='Míyágí:BAAALgAECgEJAQABLgAECgcJGwAYACEbAA==.',
['Mó']='Móldy:BAAALgAECgIJBgAAAA==.',
['Mö']='Mönkey:BAAALgADCgQJBAAAAA==.',
Na='Nale:BAAALgADCgcJHQAAAA==.Namesgambit:BAAALgAECgEJAQABLgAFFAMJBQATAJwfAA==.Namor:BAAALgAECgEJAgAAAA==.Nasforatu:BAAALgADCgUJBgAAAA==.Nattisca:BAAALgAECgIJAgAAAA==.Navani:BAAALgAECgUJCgAAAA==.',
Ne='Nedtusk:BAEALgADCgYJCQABLgAECggJIgASAKcSAA==.Nedvox:BAEBLgAECn8iAAISAAgJpxL6IQBiAQASAAgJpxL6IQBiAQAAAA==.Nervous:BAAALgAECgQJCwABLgAFFAEJAQALAAAAAA==.Nessà:BAAALgAECgUJCAAAAA==.Neveenn:BAABLgAECn8eAAMHAAgJcBakJwAXAgAHAAgJcBakJwAXAgAMAAEJfwV4cgAlAAAAAA==.Neverbakdown:BAAALgAECgQJCwAAAA==.Neverclaws:BAAALgADCgEJAQAAAA==.Nevernoctis:BAAALgADCggJEwAAAA==.',
Ni='Nightpigas:BAAALgADCgkJCwABLgAECgUJDwALAAAAAA==.',
No='Nohatcat:BAABLgAECn8hAAMVAAgJsiLDBQC0AgAVAAgJsiLDBQC0AgAIAAMJUQwlZQBFAAAAAA==.Notoom:BAAALgAECgYJDQAAAA==.Noxle:BAAALgADCgIJAgAAAA==.',
Ny='Nyxara:BAABLgAECn8fAAIQAAgJChWDNQDDAQAQAAgJChWDNQDDAQAAAA==.',
['Nè']='Nèzukõ:BAABLgAECn8VAAIOAAgJ9BiNMQDEAQAOAAgJ9BiNMQDEAQAAAA==.',
['Nø']='Nøtfuriøus:BAAALgADCgYJBQABLgAECgYJDQALAAAAAA==.',
['Nÿ']='Nÿte:BAAALgADCggJFwAAAA==.',
Ob='Obata:BAAALgAECgQJBAAAAA==.',
Oc='Octavius:BAAALgAECgQJCgABLgAECgYJCAALAAAAAA==.',
Od='Oddbrew:BAAALgADCgEJAQAAAA==.Oddsaga:BAAALgADCgYJBgAAAA==.',
Oj='Ojore:BAEBLgAECn8WAAIZAAgJlQ4eCwBHAQAZAAgJlQ4eCwBHAQAAAA==.Ojoverde:BAACLgAFFH8NAAIQAAQJYgTnRgD0AAAQAAQJYgTnRgD0AAAuAAQKfzIAAhAACQkTHF8WAGUCABAACQkTHF8WAGUCAAAA.',
On='Ontahli:BAAALgADCgUJBQABLgAECgkJLQAGALsWAA==.',
Or='Orian:BAAALgAECgEJAQAAAA==.Orleron:BAAALgADCgEJAQAAAA==.',
Ov='Overflare:BAAALgADCgkJEgAAAA==.',
Ow='Ow:BAAALgADCgUJCQAAAA==.',
Oz='Ozmà:BAAALgAECgUJDAAAAA==.Ozzdraugr:BAAALgAECgYJCQAAAA==.Ozzfu:BAAALgAECgQJBwAAAA==.Ozzsamdi:BAAALgAECgEJAQAAAA==.Ozzskelmir:BAAALgADCgYJDAAAAA==.',
Pa='Pajamas:BAABLgAECn8YAAIJAAgJrBkVEACzAQAJAAgJrBkVEACzAQAAAA==.Pallanquin:BAAALgAECgMJBQAAAA==.Pallywacker:BAAALgAECgYJEwAAAA==.Papichili:BAAALgADCgkJDAAAAA==.Pashnir:BAAALgADCggJCQAAAA==.',
Pe='Peachey:BAABLgAECn8iAAIUAAgJLxV1IwDiAQAUAAgJLxV1IwDiAQAAAA==.Peaker:BAAALgAECgIJAwAAAA==.',
Ph='Phrantic:BAAALgAECgMJBAAAAA==.Phö:BAAALgADCgcJBwAAAA==.',
Pi='Pigas:BAAALgAECgUJDwAAAA==.Pikkel:BAAALgADCgIJAgAAAA==.Pillory:BAAALgADCgYJBgAAAA==.',
Pl='Platinïum:BAAALgAECgYJBgAAAA==.Playdoh:BAAALgADCgEJAQAAAA==.',
Pr='Priestling:BAAALgADCgkJDAAAAA==.Prncess:BAAALgAECgQJCAAAAA==.Prncsspuddlz:BAABLgAECn8YAAIHAAcJ8QXWXADbAAAHAAcJ8QXWXADbAAABLgAECgQJCAALAAAAAA==.',
Ps='Psychosix:BAABLgAECn81AAIDAAkJgyT5BAA+AwADAAkJgyT5BAA+AwAAAA==.Psychros:BAAALgAECgUJBQAAAA==.',
Pu='Puzzledmind:BAAALgAECgMJAwAAAA==.',
['Pø']='Pøintblank:BAAALgADCgEJAQAAAA==.',
Qi='Qimiao:BAAALgAECgQJBgAAAA==.',
Qu='Quinberos:BAAALgADCgQJBAABLgAECgkJFQAeALEYAA==.',
Ra='Radchad:BAAALgAECgQJBQAAAA==.Raiistlin:BAAALgAECgEJAQABLgAECgYJHQANAJUgAA==.Raiola:BAAALgAECgYJDwAAAA==.Rakuumn:BAAALgAECgEJAQABLgAECgEJAgALAAAAAA==.Ramdel:BAAALgAECgYJBgABLgAECgkJIgAEAHkdAA==.Ramstryder:BAABLgAECn8iAAIEAAkJeR22CABXAgAEAAkJeR22CABXAgAAAA==.Rancidgravy:BAAALgADCgUJBgAAAA==.Rancor:BAAALgADCgEJAQAAAA==.Rapture:BAAALgADCgQJBAAAAA==.Rastabastion:BAACLgAFFH8UAAIFAAUJLCJCAgDsAQAFAAUJLCJCAgDsAQAuAAQKfx8AAgUACAlrJdsCADYDAAUACAlrJdsCADYDAAAA.',
Re='Rejuvanator:BAAALgADCgcJCAAAAA==.Rekmortal:BAABLgAFFH8LAAMmAAUJCBnLDAAVAQAmAAUJCRPLDAAVAQABAAQJ0hTXIADiAAAAAA==.Rekoj:BAAALgADCgQJBAAAAA==.Rengell:BAABLgAECn8pAAIOAAkJgRaJHgAgAgAOAAkJgRaJHgAgAgAAAA==.Resinya:BAAALgAECgcJCAAAAA==.Retnuh:BAAALgAECgEJAQAAAA==.',
Rh='Rhaazst:BAAALgADCgUJBQAAAA==.Rheagall:BAABLgAECn8ZAAIkAAgJNCDKAwB0AgAkAAgJNCDKAwB0AgAAAA==.Rheagnar:BAAALgADCgIJAgAAAA==.',
Rm='Rmeech:BAAALgAECgYJDAAAAA==.',
Ro='Roaraxe:BAAALgAECgQJBAABLgAECgYJCAALAAAAAA==.Rowena:BAABLgAECn8rAAIMAAkJiRo8FQBnAgAMAAkJiRo8FQBnAgAAAA==.Rowynna:BAABLgAECn8VAAMeAAkJsRgcCwC/AQAeAAcJihkcCwC/AQANAAIJJhbo5AB8AAAAAA==.Roxydk:BAAALgAECgcJDAAAAA==.Roxymonk:BAAALgAECggJDwAAAA==.',
Ru='Ruxspin:BAABLgAECn8VAAMVAAYJMgaEPAC/AAAVAAYJMgaEPAC/AAAIAAYJBAIYVwBuAAAAAA==.',
Ry='Ryzedvoid:BAABLgAECn8RAAIgAAYJhwmHggDGAAAgAAYJhwmHggDGAAAAAA==.Ryzinneko:BAACLgAFFH8HAAIHAAMJXBk4IQABAQAHAAMJXBk4IQABAQAuAAQKfyYAAgcACQlRINQTAGcCAAcACQlRINQTAGcCAAAA.',
Sa='Sabend:BAACLgAFFH8ZAAMQAAcJPRDNCACdAQAQAAYJaRPNCACdAQAWAAEJYAAvGgBIAAAuAAQKfx8AAxAACAmgHWApAGsCABAACAmgHWApAGsCABYAAQkAAGRmAEMAAAAA.Sablewolfe:BAAALgAECgIJAwAAAA==.Safaria:BAABLgAECn8aAAIMAAcJMh3cEwDgAQAMAAcJMh3cEwDgAQAAAA==.Sarlyssa:BAAALgADCgkJEwAAAA==.Sathran:BAAALgADCgIJAgAAAA==.Saucymac:BAACLgAFFH8MAAISAAQJlw0hEQAuAQASAAQJlw0hEQAuAQAuAAQKfzMAAxIACQm/ISIDAAYDABIACQm/ISIDAAYDAB8ABQluHMwaAKgBAAAA.',
Sc='Scofflaw:BAAALgADCgYJBgAAAA==.',
Se='Senath:BAABLgAECn8lAAMCAAcJ8R3sFwCDAQACAAYJgx3sFwCDAQAhAAIJ8h4KEwCtAAAAAA==.Sephrenia:BAAALgADCgcJCwAAAA==.Serandipity:BAAALgAECggJEwABLgAFFAQJEwAJAJoZAA==.Seraphina:BAAALgAECgEJAQAAAA==.',
Sh='Shalorath:BAABLgAECn8dAAIDAAgJGgudbQBgAQADAAgJGgudbQBgAQAAAA==.Shamanagans:BAAALgAECgYJCgAAAA==.Shamanigans:BAABLgAECn8ZAAIUAAgJXA8aMQCTAQAUAAgJXA8aMQCTAQAAAA==.Shammygoat:BAABLgAECn8UAAIYAAgJPxoNGADQAQAYAAgJPxoNGADQAQAAAA==.Shamncheese:BAAALgAECgQJAwAAAA==.Shania:BAAALgADCgUJBQAAAA==.Shaosun:BAAALgAECgYJDwABLgAECgYJEgALAAAAAA==.Shaqattack:BAACLgAFFH8JAAIVAAQJixlVCABKAQAVAAQJixlVCABKAQAuAAQKfxwAAhUACAkVI0wGABwDABUACAkVI0wGABwDAAAA.Shaqattaq:BAAALgAECgcJEQABLgAFFAQJCQAVAIsZAA==.Sharkmeat:BAABLgAECn8qAAISAAkJCxsLCQB2AgASAAkJCxsLCQB2AgAAAA==.Sharktide:BAAALgADCgkJCQAAAA==.Shauriena:BAAALgADCgUJBwAAAA==.Shawnellie:BAAALgAECgcJDAAAAA==.Shawntelle:BAABLgAECn8gAAIEAAkJEiDQBQCwAgAEAAkJEiDQBQCwAgAAAA==.Shenlune:BAAALgAECgUJCQAAAA==.Sheutka:BAAALgAECgYJEQAAAA==.Shinaie:BAABLgAECn8jAAISAAgJpAzXIgBaAQASAAgJpAzXIgBaAQAAAA==.Shockanduwu:BAABLgAECn8UAAIYAAcJuRjrJgBdAQAYAAcJuRjrJgBdAQAAAA==.Shruikan:BAAALgADCgYJDAABLgAECggJFgAFAIcWAA==.Shtylez:BAAALgAECgUJAgAAAA==.Shurshott:BAAALgADCgcJCQAAAA==.',
Si='Sigzil:BAAALgADCgUJCQAAAA==.Silth:BAAALgADCgkJJgAAAA==.Silvermisst:BAAALgAECgQJBAAAAA==.Silvermist:BAAALgADCgUJBQAAAA==.Silvertouch:BAAALgAECgEJAQABLgAECgUJBwALAAAAAA==.Sinariel:BAABLgAECn8iAAMIAAgJVhuxEgAcAgAIAAcJ1BuxEgAcAgAVAAgJtBLVKgCHAQAAAA==.Sirdank:BAAALgADCgMJAwAAAA==.Sithus:BAAALgADCgQJBAAAAA==.',
Sl='Sliko:BAABLgAECn8WAAINAAkJkQlKZQBaAQANAAkJkQlKZQBaAQAAAA==.',
Sm='Smmoke:BAABLgAECn8sAAIOAAkJdB2OHQAmAgAOAAkJdB2OHQAmAgAAAA==.Smorko:BAAALgADCgYJBgAAAA==.',
Sn='Sneekypally:BAAALgAECgMJBgAAAA==.Sniperart:BAABLgAECn8hAAIOAAkJthv7EQB5AgAOAAkJthv7EQB5AgABLgAECgkJKgAJAIghAA==.',
So='Sothh:BAAALgADCgYJBgABLgAECgYJHQANAJUgAA==.Soull:BAABLgAECn8iAAIHAAkJph0QCAD7AgAHAAkJph0QCAD7AgAAAA==.',
Sp='Spacemoo:BAABLgAECn8dAAQKAAcJ3R1IPwDAAQAKAAcJiR1IPwDAAQAZAAQJDBLTFACuAAAJAAEJhAFmSgAeAAAAAA==.',
Sq='Squall:BAAALgADCgcJCAAAAA==.Squashfoot:BAAALgADCgQJAwABLgAECgYJCAALAAAAAA==.',
St='Starface:BAACLgAFFH8RAAIXAAQJkRA0CADmAAAXAAQJkRA0CADmAAAuAAQKfzIAAxcACQknH8MCAMMCABcACQknH8MCAMMCAAcAAQk9AfDpABsAAAAA.Stargoose:BAAALgAECgcJBwABLgAFFAQJEQAXAJEQAA==.Starrlyte:BAAALgADCgUJBQAAAA==.Steelytree:BAAALgAECgQJBQAAAA==.Stefane:BAAALgAECgcJCgAAAA==.Sterrling:BAAALgADCggJBwAAAA==.Steverogers:BAAALgAECgUJCgABLgAFFAMJBQATAJwfAA==.Stocktonrush:BAAALgAECgMJBQABLgAFFAMJBQATAJwfAA==.Stonewillow:BAAALgADCgUJBQAAAA==.Stormoond:BAAALgADCgEJAQAAAA==.Strongbad:BAAALgAECgYJEgAAAA==.Sturmx:BAABLgAECn8sAAInAAkJfRg7CQA7AgAnAAkJfRg7CQA7AgAAAA==.',
Su='Subaaâ:BAABLgAECn8hAAMaAAgJliMGAQAzAwAaAAgJliMGAQAzAwAgAAUJIhQ9hgAaAQABLgAECggJLAABAPAcAA==.Subby:BAAALgADCgYJDwAAAA==.Subedei:BAACLgAFFH8HAAIKAAMJUhaZXAD4AAAKAAMJUhaZXAD4AAAuAAQKfywAAwkACQkeIkUGANMCAAkACAk7IkUGANMCAAoABQnlGjrUANgAAAAA.Sukati:BAAALgADCgMJAwAAAA==.Sunderhorn:BAAALgAECgYJEQAAAA==.Sutherman:BAAALgAECgEJAQAAAA==.',
Sv='Svictis:BAABLgAECn8jAAIKAAgJMBOXYwBXAQAKAAgJMBOXYwBXAQAAAA==.Sviictis:BAAALgADCggJEgAAAA==.',
Sw='Swab:BAAALgADCgEJAQABLgADCggJGAALAAAAAA==.Swami:BAAALgADCgQJBAAAAA==.',
Sy='Syluxs:BAABLgAECn8gAAInAAgJkBXIEAC1AQAnAAgJkBXIEAC1AQAAAA==.Syrony:BAAALgAECgEJAQAAAA==.',
['Sû']='Sûshealä:BAABLgAECn8VAAIfAAYJgRWLJQBPAQAfAAYJgRWLJQBPAQAAAA==.',
Ta='Tabby:BAAALgADCgkJCQAAAA==.Tadryth:BAAALgADCgQJBQAAAA==.Talila:BAABLgAECn8sAAIXAAYJvB9QCwDCAQAXAAYJvB9QCwDCAQAAAA==.Tamashi:BAAALgADCgIJAgAAAA==.Taxter:BAAALgADCgEJAQAAAA==.',
Te='Tealzitaz:BAAALgAECgEJAgAAAA==.Terrya:BAAALgADCgkJDgAAAA==.Teryail:BAAALgAECgYJCwAAAA==.',
Th='Thallion:BAAALgAECgMJBAAAAA==.Thalorian:BAAALgADCgIJAgAAAA==.Thaqknight:BAAALgAECgkJCQAAAA==.Tharaa:BAAALgAECgUJBwAAAA==.Theycomeforu:BAAALgAECggJCgAAAA==.Thiccklock:BAAALgAECgUJBgAAAA==.Thily:BAAALgAECgEJAQAAAA==.Thorwallen:BAAALgADCgYJDAABLgAECgYJHQANAJUgAA==.',
Ti='Tickle:BAABLgAECn8bAAIlAAcJOyHaBQAzAgAlAAcJOyHaBQAzAgAAAA==.Tiermorthius:BAAALgADCgYJBgABLgAECgUJCwALAAAAAA==.Tirithor:BAABLgAECn8zAAINAAkJwBXNMAD1AQANAAkJwBXNMAD1AQAAAA==.',
To='Tockell:BAAALgAECgMJAwAAAA==.Tonakai:BAACLgAFFH8HAAIMAAQJuAMZIADNAAAMAAQJuAMZIADNAAAuAAQKfxUAAgwACQn0F3MKAGECAAwACQn0F3MKAGECAAAA.Tony:BAAALgAECgYJCgABLgAFFAMJCgAVAAMWAA==.Torbin:BAABLgAECn8UAAIOAAcJvAe/ZQAcAQAOAAcJvAe/ZQAcAQAAAA==.Touchmywave:BAAALgADCgUJCAABLgAECgcJEgALAAAAAA==.',
Tr='Tricks:BAAALgAECgcJEAAAAA==.Trill:BAAALgADCggJBAABLgAECgYJBwALAAAAAA==.Trilleon:BAAALgAECgYJBwAAAA==.Trillis:BAAALgAECgIJAgABLgAECgYJBwALAAAAAA==.Tryjincks:BAAALgAECgYJDAAAAA==.Tryjinks:BAAALgAECgYJCgABLgAECgYJDAALAAAAAA==.',
Ts='Tserendolgor:BAAALgADCgEJAQAAAA==.',
Tu='Turgà:BAAALgAECgEJAQABLgAECgUJCAALAAAAAA==.',
Ty='Tykahndrius:BAAALgAECgEJAQAAAA==.Tylîus:BAAALgAECgQJBAABLgAECgYJFgAeAKgbAA==.Tys:BAAALgADCgQJBAAAAA==.',
['Tö']='Töph:BAAALgADCgEJAQABLgAECgUJCAALAAAAAA==.',
['Tú']='Túsk:BAAALgAECgcJCgAAAA==.',
['Tý']='Týlïus:BAABLgAECn8WAAIeAAYJqBvzEgCbAQAeAAYJqBvzEgCbAQAAAA==.',
Ud='Uddergrace:BAAALgADCgEJAQAAAA==.',
Un='Unspokenword:BAAALgADCggJGAAAAA==.',
Ut='Uthilon:BAABLgAECn8rAAIeAAkJ4CHMAQDjAgAeAAkJ4CHMAQDjAgAAAA==.',
Va='Vaeredor:BAAALgADCgIJAgAAAA==.Valdare:BAABLgAECn8hAAInAAYJSBJyHwAVAQAnAAYJSBJyHwAVAQAAAA==.',
Ve='Vedillian:BAABLgAECn8kAAIiAAgJyg1vBwB5AQAiAAgJyg1vBwB5AQAAAA==.Velyndrenis:BAAALgADCgEJAgAAAA==.Vennaya:BAABLgAECn8fAAIfAAkJlgeHLgAQAQAfAAkJlgeHLgAQAQAAAA==.Vethinrel:BAAALgADCgYJBgAAAA==.',
Vi='Victorr:BAAALgAECgEJAQAAAA==.Viktorius:BAAALgADCgkJCQAAAA==.Violentpanda:BAAALgAECgYJDgABLgAECggJLAADAK8kAA==.Vite:BAAALgADCggJIAAAAA==.Vixious:BAAALgADCgcJEgAAAA==.Vizigoth:BAABLgAECn8qAAMQAAgJpA2qTwBtAQAQAAcJpA2qTwBtAQAWAAIJCxHzVwBnAAAAAA==.',
Vo='Voladon:BAABLgAECn8hAAIHAAcJcxiVJQDaAQAHAAcJcxiVJQDaAQAAAA==.Voyana:BAABLgAECn8ZAAIfAAcJlBMpHgCKAQAfAAcJlBMpHgCKAQABLgAECgcJGgAMADIdAA==.',
Vy='Vydragon:BAAALgAFFAIJAgABLgAFFAQJEwADAPQXAA==.Vymage:BAACLgAFFH8TAAIDAAQJ9BfSMwBQAQADAAQJ9BfSMwBQAQAuAAQKfzAAAwMACQmWInMJAAIDAAMACQmWInMJAAIDACgABAn9EFMGAOsAAAAA.',
['Vá']='Válidüs:BAACLgAFFH8YAAIfAAUJyRKyBwBwAQAfAAUJyRKyBwBwAQAuAAQKfyEAAh8ACQmgHcYLAJQCAB8ACQmgHcYLAJQCAAAA.',
['Vã']='Vãsh:BAABLgAECn8VAAQTAAYJfgZrQAC/AAATAAYJfgZrQAC/AAAVAAUJZAK+WwBWAAAIAAEJhgHQgAAWAAAAAA==.',
Wa='Wanitou:BAAALgADCgMJAwAAAA==.Warninja:BAABLgAECn8XAAIhAAgJxQsYCQBrAQAhAAgJxQsYCQBrAQAAAA==.Waterlogged:BAAALgADCgMJAwAAAA==.Waterloo:BAAALgAECgEJAQAAAA==.',
We='Weejas:BAAALgADCgMJAwAAAA==.Werwick:BAAALgAECggJDgAAAA==.',
Wh='Whatsnail:BAABLgAECn8cAAIDAAgJpwmkdgBNAQADAAgJpwmkdgBNAQAAAA==.',
Wi='Wizdom:BAAALgADCgQJBAAAAA==.Wizpigas:BAAALgADCgQJBAABLgAECgUJDwALAAAAAA==.',
Wr='Wrathidan:BAAALgAECggJEgAAAA==.',
['Wì']='Wìccka:BAABLgAECn8WAAIHAAYJVxovKQDDAQAHAAYJVxovKQDDAQAAAA==.',
Xi='Xifan:BAAALgAECgEJAgAAAA==.',
Ya='Yalper:BAAALgADCgcJCwAAAA==.',
Yd='Yd:BAAALgAECgIJAgABLgAFFAMJBgACAOcdAA==.',
Yo='Youngwokongs:BAAALgADCgIJAgAAAA==.',
Yu='Yudie:BAABLgAECn8XAAIIAAYJoQ6uNQAYAQAIAAYJoQ6uNQAYAQAAAA==.',
Yw='Ywontudie:BAAALgADCgYJDAAAAA==.',
Yz='Yz:BAACLgAFFH8GAAICAAMJ5x0wFQAZAQACAAMJ5x0wFQAZAQAuAAQKfxwAAgIACQneIaYBAB8DAAIACQneIaYBAB8DAAAA.',
Za='Zalysi:BAABLgAECn8WAAMRAAgJHBLhJwDtAQARAAgJHBLhJwDtAQANAAIJkQdLHwFeAAAAAA==.Zam:BAABLgAECn8dAAMBAAcJ5B3VHwBSAgABAAcJsRrVHwBSAgAmAAMJ0hi2NACPAAAAAA==.Zamantha:BAAALgADCgIJAgAAAA==.Zanny:BAAALgADCgMJAwAAAA==.Zashawa:BAAALgADCgcJCAAAAA==.Zashen:BAAALgAECgcJDQAAAA==.',
Ze='Zebb:BAAALgADCgcJDQAAAA==.Zelix:BAAALgADCgEJAQAAAA==.Zenmist:BAAALgAECgUJBwAAAA==.Zeylanica:BAAALgAECgEJAQABLgAFFAQJEQAXAJEQAA==.',
Zh='Zhastr:BAAALgAECgYJEAAAAA==.',
Zl='Zllusion:BAAALgADCgMJAwAAAA==.Zlucu:BAAALgAECgQJBwABLgAFFAQJCwAQAPgTAA==.Zlufernal:BAACLgAFFH8LAAIQAAQJ+BPmNgAhAQAQAAQJ+BPmNgAhAQAuAAQKfy4AAhAACQl2IVMNAA8DABAACQl2IVMNAA8DAAAA.',
Zy='Zyn:BAABLgAECn8eAAIBAAcJnQ78MAA5AQABAAcJnQ78MAA5AQAAAA==.',
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
