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

local lookup = {'Priest-Shadow','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','Monk-Brewmaster','Evoker-Preservation','Hunter-BeastMastery','Monk-Windwalker','Priest-Holy','DemonHunter-Havoc','DeathKnight-Blood','Warrior-Fury','Warrior-Protection','Shaman-Restoration','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','Druid-Balance','Unknown-Unknown','Druid-Restoration','Druid-Guardian','Druid-Feral','Warrior-Arms','Paladin-Protection','Priest-Discipline','Warlock-Destruction','Warlock-Demonology','Paladin-Holy','Shaman-Elemental','Rogue-Assassination','Warlock-Affliction','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Vengeance',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abukuma:BAAALgAECgQJBAAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAABLgAECn8RAAIBAAgJAQY6VQCTAAABAAgJAQY6VQCTAAAAAA==.Aenstalash:BAABLgAECn8hAAICAAgJPyPeHQB7AgACAAgJPyPeHQB7AgAAAA==.Aephium:BAABLgAECn8UAAMDAAcJuwZdWQCnAAADAAYJJgZdWQCnAAAEAAUJtARxGQBxAAAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8kAAIFAAkJiBdkPAD8AQAFAAkJiBdkPAD8AQAAAA==.',
Af='Afflictia:BAAALgADCgYJEAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alaure:BAAALgADCgIJAgAAAA==.Alessia:BAAALgAECgIJAgAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAABLgAECn8YAAIGAAgJAAcsngAjAQAGAAgJAAcsngAjAQAAAA==.',
Am='Amanna:BAAALgAECgMJAwABLgAECggJHQAHAPUiAA==.Amoona:BAAALgAECgYJEgABLgAECggJHQAHAPUiAA==.',
An='Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arcnid:BAAALgADCgYJBgAAAA==.Arfas:BAAALgADCgQJBAAAAA==.Arthraz:BAABLgAECn8kAAIIAAkJsxyfCgB5AgAIAAkJsxyfCgB5AgAAAA==.',
As='Astara:BAAALgAECgQJBAAAAA==.Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAABLgAECn8oAAMJAAcJ+g6CFQBiAQAJAAcJ+g6CFQBiAQADAAEJJwHDlgAOAAAAAA==.',
Au='Aunaturale:BAAALgAECgkJAwAAAA==.Aureliá:BAABLgAECn8XAAIKAAcJnQoHewAwAQAKAAcJnQoHewAwAQAAAA==.',
['Aü']='Aütobot:BAABLgAECn8iAAILAAkJMw1MIQCOAQALAAkJMw1MIQCOAQAAAA==.',
Ba='Badgirl:BAACLgAFFH8JAAIMAAMJSA4PHgClAAAMAAMJSA4PHgClAAAuAAQKfxkAAwwACAm+EwoxADEBAAwABgnBFgoxADEBAAEABgktCo5FANIAAAAA.Balnar:BAAALgAFFAEJAQAAAA==.Balraga:BAABLgAECn8ZAAINAAgJUQorJQAqAQANAAgJUQorJQAqAQAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Bega:BAACLgAFFH8fAAMFAAgJ/RnmBwBfAgAFAAcJ/RnmBwBfAgAOAAEJAADdSQAAAAAuAAQKf0EAAwUACQnoJewDAFgDAAUACQnoJewDAFgDAA4ABgkrFzslABUBAAAA.Benton:BAAALgAECgQJCAAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Bloodlustplz:BAABLgAECn8qAAMPAAkJshdJJwCrAQAPAAcJLx5JJwCrAQAQAAgJLQ+TGABhAQAAAA==.',
Bo='Bobster:BAABLgAECn8kAAIGAAkJuxETWwC0AQAGAAkJuxETWwC0AQAAAA==.Bonepaw:BAAALgAECgEJAQABLgAECgcJFAARAHwVAA==.Booyea:BAABLgAECn89AAIOAAkJ4RtjCQBnAgAOAAkJ4RtjCQBnAgAAAA==.',
Br='Brewwnor:BAAALgAECgcJCwAAAA==.Brickdemkeys:BAABLgAECn8fAAIGAAgJPBpsWQC5AQAGAAgJPBpsWQC5AQAAAA==.Brisfloggnaw:BAAALgAFFAEJAQAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAcJHAASAAgfAA==.Calamuelis:BAACLgAFFH8cAAQSAAcJCB9EBwCBAQATAAcJ7hvWBwCeAQASAAUJTyJEBwCBAQAKAAEJ1CN9eQBqAAAuAAQKfx0ABBMACAnSJLsNANcCABMACAmWJLsNANcCABIABAn5JO4sAC0BAAoAAQkIJvLbAGoAAAAA.Caliope:BAABLgAECn8VAAIUAAcJWhXFKQCwAQAUAAcJWhXFKQCwAQAAAA==.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAECgkJBwAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celery:BAAALgADCgQJBwABLgAECgkJJAAIALMcAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8dAAIVAAUJARDLSQAEAQAVAAUJARDLSQAEAQAAAA==.Ceredis:BAAALgAECgEJAQAAAA==.Cerelus:BAABLgAECn8gAAIGAAkJWA+STADeAQAGAAkJWA+STADeAQAAAA==.',
Ch='Chaac:BAAALgAECgYJBgABLgAECggJDwAWAAAAAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAABLgAECn8WAAUXAAgJVh4ANwDLAQAXAAYJUyAANwDLAQAYAAQJCx7wEQBVAQAVAAIJih+xUQCrAAAZAAEJLwbeMgA2AAAAAA==.',
Cl='Clax:BAAALgAECgIJBQAAAA==.',
Co='Cobeam:BAAALgAECgUJEQAAAA==.Cowpernicus:BAABLgAECn8hAAIXAAgJdiGKCwD1AgAXAAgJdiGKCwD1AgABLgAFFAIJBgARAJMdAA==.',
Cr='Crungleman:BAABLgAECn8YAAIKAAcJuRh7UQCVAQAKAAcJuRh7UQCVAQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAABLgAECggJDwAWAAAAAA==.',
Cu='Curoi:BAABLgAECn8rAAMZAAkJjxcuBwBHAgAZAAkJjxcuBwBHAgAXAAgJRAozeQDsAAAAAA==.',
['Cã']='Cãrloy:BAACLgAFFH8UAAIPAAQJchllGQA3AQAPAAQJchllGQA3AQAuAAQKf0sAAw8ACQmGIbEJABMDAA8ACQmGIbEJABMDABoAAgl5H2ksAJEAAAAA.',
['Cê']='Cêlestial:BAABLgAECn8dAAMHAAgJ9SKzGABtAgAHAAgJ9SKzGABtAgANAAIJfBxtUwBNAAAAAA==.',
Da='Daedalas:BAABLgAECn8WAAMBAAgJnx/aDABqAgABAAgJnx/aDABqAgAMAAIJMAKTYgA9AAAAAA==.Damonk:BAAALgADCgYJBgABLgAECgkJIAAQAOIaAA==.Danevolent:BAABLgAECn8gAAMMAAcJ9yJ9DQCAAgAMAAcJ9yJ9DQCAAgABAAQJEA1aUwCaAAABLgAECgkJIAAQAOIaAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAABLgAECn8cAAIbAAcJORTcFQBbAQAbAAcJORTcFQBbAQABLgAFFAEJAQAWAAAAAA==.Darthknull:BAACLgAFFH8RAAICAAQJhxHrNgAmAQACAAQJhxHrNgAmAQAuAAQKfzEAAgIACQkwHlAoAEkCAAIACQkwHlAoAEkCAAAA.Darthtalon:BAAALgAECgcJCAABLgAFFAQJEQACAIcRAA==.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathniight:BAAALgAECgUJBAAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgUJBgABLgAECgEJAQAWAAAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8lAAITAAkJnxkkBgAfAgATAAkJnxkkBgAfAgAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestrea:BAABLgAECn8ZAAIOAAYJsQ5mKQDyAAAOAAYJsQ5mKQDyAAAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dippindots:BAAALgAECgYJCAAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAgJIgADANEhAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Dolfcrittler:BAAALgADCgEJAQAAAA==.Donkform:BAAALgAECgkJEgAAAA==.Donniyii:BAAALgADCgcJBwABLgAECgkJNwAcAJQfAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAABLgAECn8aAAIdAAYJ8B27FQCcAQAdAAYJ8B27FQCcAQAAAA==.',
Dr='Draconith:BAACLgAFFH8OAAIJAAUJNAz0EgBEAQAJAAUJNAz0EgBEAQAuAAQKfy0AAgkACQnfF00IAFsCAAkACQnfF00IAFsCAAAA.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAABLgAECn8ZAAIKAAYJVQomlAD8AAAKAAYJVQomlAD8AAAAAA==.Dreddwing:BAAALgAECggJDwAAAA==.Drunkenoodle:BAAALgADCgYJBgAAAA==.',
Du='Dunsparrow:BAACLgAFFH8GAAIRAAIJkx2zSQCsAAARAAIJkx2zSQCsAAAuAAQKf0YAAhEACQm2IlwEAF0DABEACQm2IlwEAF0DAAAA.Durzul:BAAALgAECgEJAQAAAA==.',
Ei='Eightyone:BAAALgAECggJDwAAAA==.Eindraken:BAACLgAFFH8JAAIJAAUJYwLtGQDfAAAJAAUJYwLtGQDfAAAuAAQKfzgAAgkACQn7EhkMAAMCAAkACQn7EhkMAAMCAAAA.Eiroh:BAAALgAECgQJBAABLgAECggJHgAbAPERAA==.Eisis:BAABLgAECn8+AAIZAAkJVBBHEQCAAQAZAAkJVBBHEQCAAQAAAA==.',
El='Elanalué:BAAALgAECgQJBgABLgAECgcJFQAUAFoVAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.Erroz:BAAALgADCgIJAQAAAA==.',
Es='Eshonäi:BAABLgAECn8aAAIeAAYJtRHIhAAlAQAeAAYJtRHIhAAlAQAAAA==.Espriesso:BAAALgAECgcJEQABLgAECgkJJAAIANgNAA==.',
Ev='Evodragker:BAABLgAECn8kAAMDAAkJKxRXHQDTAQADAAkJKxRXHQDTAQAJAAEJcAkLNwA0AAAAAA==.',
Fe='Feider:BAAALgAECgEJAQAAAA==.Felais:BAAALgAECgEJAgAAAA==.Feldron:BAAALgAECgcJEwAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgAECgYJDAAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.',
Fl='Flamecube:BAAALgADCgcJCAAAAA==.Flashx:BAABLgAECn8eAAMfAAcJ6iG3DQCiAgAfAAcJ6iG3DQCiAgACAAEJQQwTlAEkAAAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAgAAAA==.Frofrohunter:BAABLgAECn8sAAMKAAkJaB+kEgCiAgAKAAkJaB+kEgCiAgATAAUJAxLZTgAUAQAAAA==.Frofrolock:BAAALgAECgcJDgAAAA==.Froggie:BAABLgAECn8UAAMRAAcJfBVFSABwAQARAAcJfBVFSABwAQAgAAMJXQ/iaACgAAAAAA==.Froshaman:BAAALgAECgEJAQAAAA==.',
Fu='Fuzywuuzy:BAACLgAFFH8MAAIXAAMJ1BS3MwDPAAAXAAMJ1BS3MwDPAAAuAAQKfyUAAxcACAnUI1EKAAYDABcACAnUI1EKAAYDABUABwk6FuojAJEBAAAA.',
Ga='Gazdorn:BAABLgAECn8qAAIQAAkJeRLpDwDRAQAQAAkJeRLpDwDRAQAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8hAAIhAAgJdhr3BAAhAgAhAAgJdhr3BAAhAgAAAA==.',
Gi='Gigof:BAABLgAECn8rAAMVAAkJPxKLIQCiAQAVAAgJ0RKLIQCiAQAXAAcJ/Ap8egC2AAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQiAAcJdCWRAQDTAgAiAAcJEiWRAQDTAgAeAAMJhSJYogAUAQAdAAIJjxpcRACkAAAAAA==.',
Go='Gobah:BAABLgAECn8YAAMjAAgJ5hVyFgDSAQAjAAgJ5hVyFgDSAQAkAAUJsQedFACqAAAAAA==.',
Gt='Gt:BAAALgAECgMJBQAAAA==.',
Gu='Gulldan:BAABLgAECn8hAAIeAAgJtBe7MQAFAgAeAAgJtBe7MQAFAgAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Habanero:BAAALgAECgQJBgABLgAECgkJJAAIALMcAA==.Hadory:BAAALgAECgYJDAABLgAECgcJFgARAH8jAA==.Harrowhark:BAABLgAECn82AAQiAAkJkwk4DwBJAQAeAAkJ+Qd9XQB8AQAiAAgJuwk4DwBJAQAdAAQJyQX3KwBZAAAAAA==.',
He='Hellzzdemon:BAABLgAECn8WAAINAAcJFg2bJwAYAQANAAcJFg2bJwAYAQAAAA==.Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgQJBQAAAA==.Hexzard:BAAALgADCgQJBAABLgAECgUJEQAWAAAAAA==.Hezekiiah:BAAALgAECgYJCQAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAFFAIJBgARAJMdAA==.Holycannoli:BAAALgAECgcJCwAAAA==.Horiffic:BAAALgAECgcJEgAAAA==.Horok:BAAALgAECgYJDAAAAA==.Hotwheels:BAAALgAECgMJAwAAAA==.',
Hu='Hubert:BAABLgAECn8WAAIUAAgJwQm3SAAUAQAUAAgJwQm3SAAUAQAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAcJFgAHAPMSAA==.',
Ic='Ichaerus:BAAALgAECgQJBQABLgAECggJFgABAJ8fAA==.Ichtheblack:BAAALgAECgIJAgABLgAECggJFgABAJ8fAA==.Ichtu:BAAALgAECgEJAQABLgAECggJFgABAJ8fAA==.',
Ii='Iilli:BAABLgAECn83AAMcAAkJlB8wBgAHAwAcAAkJlB8wBgAHAwABAAgJJBkYFwD0AQAAAA==.',
In='Inari:BAABLgAECn8WAAIBAAgJvwuEMQA0AQABAAgJvwuEMQA0AQAAAA==.Inkkubus:BAACLgAFFH8VAAQdAAUJDx15EQCTAAAeAAMJQh9UWgD5AAAdAAIJ+g55EQCTAAAiAAIJww1FHgBMAAAuAAQKfxcABB4ACQmPHi81APcBAB4ABwnZHy81APcBAB0AAwnpGy4UAPAAACIAAQkAABEnAFUAAAAA.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Iw='Iwkms:BAACLgAFFH8OAAIZAAQJihYNBgAuAQAZAAQJihYNBgAuAQAuAAQKfyMAAhkACAliIzMCADEDABkACAliIzMCADEDAAEuAAUUBQkGACQAwhYA.',
Ja='Jade:BAABLgAECn8dAAIIAAYJ9CTjEwAAAgAIAAYJ9CTjEwAAAgAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jenliz:BAAALgADCgEJAQABLgAECgYJEQAWAAAAAA==.Jeronor:BAAALgAECgIJAgAAAA==.',
Ji='Jimmick:BAABLgAECn8WAAIRAAcJfyOTDgDHAgARAAcJfyOTDgDHAgAAAA==.Jisung:BAAALgAECgYJEwAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Jt='Jtheman:BAAALgAECgQJBAAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgYJCwAAAA==.Kaissa:BAAALgAECgEJAQAAAA==.Kalena:BAABLgAECn89AAIGAAkJ5w55WAC7AQAGAAkJ5w55WAC7AQAAAA==.Kandikkiss:BAAALgAECgEJAQAAAA==.Kaos:BAABLgAECn8jAAIGAAkJ+hF8VwC+AQAGAAkJ+hF8VwC+AQAAAA==.Kariatyda:BAABLgAECn8uAAIKAAkJMxgIGwBlAgAKAAkJMxgIGwBlAgAAAA==.Kasai:BAAALgADCgMJAwABLgAECgYJHQACAL4XAA==.Kassandra:BAACLgAFFH8IAAIGAAMJ4Bf2ZgD4AAAGAAMJ4Bf2ZgD4AAAuAAQKfz0AAgYACQnvHAoYALMCAAYACQnvHAoYALMCAAAA.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8aAAIUAAYJhBh2JACQAQAUAAYJhBh2JACQAQABLgAECggJGwAfAFUcAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kelisola:BAAALgADCgEJAQAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.',
Ki='Kiloton:BAABLgAECn8hAAIYAAgJ5xHXGgBSAQAYAAgJ5xHXGgBSAQAAAA==.Kinari:BAAALgAECgcJCgAAAA==.Kitzy:BAABLgAECn8iAAIGAAkJ0gSjlAA0AQAGAAkJ0gSjlAA0AQAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAABLgAECn8wAAIFAAkJCBfnMQAjAgAFAAkJCBfnMQAjAgAAAA==.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAABLgAECn8qAAIXAAkJXw8XMgDEAQAXAAkJXw8XMgDEAQAAAA==.',
Ko='Korgan:BAAALgAECgQJBgAAAA==.Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgAECgIJAgAAAA==.',
Ku='Kurzo:BAACLgAFFH8GAAIPAAMJChUOKgDoAAAPAAMJChUOKgDoAAAuAAQKfzsAAw8ACQnrIjoFAP0CAA8ACQnrIjoFAP0CABAABQmtEussANoAAAAA.',
Ky='Kylarian:BAABLgAECn8iAAINAAkJyQY5JQAqAQANAAkJyQY5JQAqAQAAAA==.Kyntara:BAAALgAECgYJDQAAAA==.Kyronian:BAAALgAECgYJDwAAAA==.',
['Kâ']='Kâsâi:BAABLgAECn8dAAICAAYJvhcEfABbAQACAAYJvhcEfABbAQAAAA==.',
La='Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECggJEwAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAABLgAECn85AAICAAkJYhN3RgDbAQACAAkJYhN3RgDbAQAAAA==.',
Li='Lightbehunt:BAAALgAECgQJBgAAAA==.Lightfivhapy:BAAALgAECgUJCQAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.Lilly:BAAALgAECgYJCgAAAA==.Livaless:BAAALgADCgQJBAABLgAECgkJJAAeACwiAA==.',
Lu='Lucialyn:BAAALgAECgcJDAABLgAECgcJFwAcAOojAA==.',
Ly='Lyllith:BAABLgAECn8cAAIhAAYJjREWDABkAQAhAAYJjREWDABkAQAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECgkJIAAQAOIaAA==.Magnius:BAAALgADCgEJAQAAAA==.Mal:BAAALgAECggJCAAAAA==.Mastablasta:BAAALgAECgQJCQAAAA==.Maursaline:BAABLgAECn8lAAIXAAkJqgeqUwAuAQAXAAkJqgeqUwAuAQAAAA==.Mawea:BAAALgAECgUJDAAAAA==.Mawks:BAABLgAECn8tAAISAAkJDRcpDgA5AgASAAkJDRcpDgA5AgAAAA==.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgUJCgAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migzeviltwin:BAAALgAECgEJAQAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Minitry:BAAALgAECgEJAQAAAA==.Mixxon:BAAALgAECgYJDgAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAABLgAECn8fAAIgAAkJMhdJGgD3AQAgAAkJMhdJGgD3AQAAAA==.Morhgana:BAAALgAECgYJDwAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8jAAMMAAgJygFjRADAAAAMAAgJygFjRADAAAABAAIJXwHWZQAtAAAAAA==.',
['Mö']='Mördecai:BAAALgAECgQJBAAAAA==.',
Na='Naija:BAAALgAECgEJAgAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Nephele:BAAALgAECgEJAQAAAA==.Neptune:BAAALgAECgQJCAAAAA==.',
Ni='Nikorobin:BAAALgAECgQJBwABLgAFFAcJFgAHAPMSAA==.Nilius:BAAALgADCgcJBwABLgAECggJFgABAJ8fAA==.',
No='Noodles:BAAALgADCgkJDAABLgAECgcJDQAWAAAAAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAABLgAECn8eAAIbAAgJ8RE+FABvAQAbAAgJ8RE+FABvAQAAAA==.',
['Ní']='Níce:BAAALgAECgIJAwAAAA==.',
['Nü']='Nügs:BAAALgAECggJEwAAAA==.Nüguns:BAAALgAECgcJCAAAAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painlink:BAAALgAECgUJCQABLgAECgkJKQAPAHkRAA==.Painnkiller:BAABLgAECn8yAAIKAAkJfhxrGgByAgAKAAkJfhxrGgByAgAAAA==.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAABLgAECn8eAAMiAAcJux/tBQADAgAiAAcJux/tBQADAgAeAAMJmxl+tgDOAAABLgAECgkJJAAIALMcAA==.Paxis:BAAALgAECgkJDgAAAA==.',
Pe='Perriwinkle:BAABLgAECn85AAQZAAkJUxwpCwAQAgAZAAkJXBspCwAQAgAYAAgJuRK1FwBvAQAXAAQJPwwZgQCnAAAAAA==.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAABLgAECn8dAAIXAAgJ0hnXHQBDAgAXAAgJ0hnXHQBDAgAAAA==.Phylloxeras:BAABLgAECn9BAAIFAAkJUyTZBQA/AwAFAAkJUyTZBQA/AwAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powders:BAABLgAECn80AAIGAAkJ5RvIJQBuAgAGAAkJ5RvIJQBuAgAAAA==.Powderysham:BAAALgAECgcJCgABLgAECgkJNAAGAOUbAA==.',
Pr='Praystatiôn:BAAALgAECgEJAQABLgAECgcJGwAeAHcfAA==.Proshot:BAABLgAECn8xAAISAAkJOCIbAgAhAwASAAkJOCIbAgAhAwAAAA==.',
Pu='Puddles:BAAALgAECgEJAQAAAA==.',
Pz='Pzalmo:BAAALgAECgMJAwABLgAECgkJHwAEAJkUAA==.',
Ra='Raccoon:BAABLgAECn89AAMeAAkJmxEkOwDhAQAeAAkJmxEkOwDhAQAiAAEJaAvfNQA2AAAAAA==.Ravenhawk:BAAALgAECgYJEAAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAABLgAECn8bAAIFAAgJPxpGLQA3AgAFAAgJPxpGLQA3AgAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAACLgAFFH8WAAIHAAcJ8xKQGQCnAQAHAAcJ8xKQGQCnAQAuAAQKfyEAAwcACQlIH2ojAH0CAAcACQlIH2ojAH0CACUAAglxEwUmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8iAAMPAAkJBRCsLgCBAQAPAAkJBRCsLgCBAQAaAAIJtgafYABCAAAAAA==.Ryrín:BAAALgAECgcJEQAAAA==.',
Sa='Samidrac:BAABLgAECn8UAAIJAAYJsgGULABsAAAJAAYJsgGULABsAAAAAA==.Sammidormu:BAABLgAECn8jAAQEAAgJ5RNECQCBAQAEAAcJABVECQCBAQADAAcJbAtZNgAgAQAJAAEJ2QEPTgAjAAAAAA==.Sanderwoof:BAAALgAECggJCAAAAA==.Sarzul:BAABLgAECn8VAAMdAAYJ/A8VNADnAAAeAAYJ2gzAmwAiAQAdAAUJThEVNADnAAAAAA==.Satoshie:BAAALgAECggJCQAAAA==.',
Sc='Scerevisiae:BAABLgAECn8UAAMeAAgJOxltdgBCAQAeAAUJwBttdgBCAQAdAAQJxBSjLgABAQAAAA==.',
Se='Sedelis:BAABLgAECn8fAAIfAAkJzwpJLQCUAQAfAAkJzwpJLQCUAQAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgAECgEJAQAAAA==.Semnai:BAABLgAECn8yAAIXAAgJTBjdHgA7AgAXAAgJTBjdHgA7AgAAAA==.Serafín:BAABLgAECn83AAIIAAkJYQz5IwB6AQAIAAkJYQz5IwB6AQAAAA==.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAECgYJDgAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shadowpyro:BAAALgAECgEJAQAAAA==.Shamwig:BAAALgADCgUJBQAAAA==.Shazzam:BAAALgAECgYJDwAAAA==.Shieldwall:BAABLgAECn8qAAIQAAgJWg+qGABgAQAQAAgJWg+qGABgAQAAAA==.',
Si='Silanah:BAAALgAECgEJAQAAAA==.Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAABLgAECn8aAAICAAgJ9RDndgBmAQACAAgJ9RDndgBmAQAAAA==.',
So='Solone:BAAALgAECgYJDAAAAA==.Sopidia:BAABLgAECn8kAAMRAAgJSRfNNgC6AQARAAcJtBbNNgC6AQAgAAUJHQYxZwCSAAAAAA==.Sorvato:BAABLgAECn8xAAIHAAgJDBg7MgDnAQAHAAgJDBg7MgDnAQAAAA==.',
Sp='Spoonzz:BAABLgAECn8xAAMLAAkJDSQ/BAAFAwALAAkJDSQ/BAAFAwAIAAIJKx9IUwCmAAAAAA==.',
St='Stamavan:BAABLgAECn8kAAIYAAkJzCJrAgD/AgAYAAkJzCJrAgD/AgAAAA==.Starflayer:BAABLgAECn8nAAMHAAkJXxwPIgA1AgAHAAkJbhsPIgA1AgAlAAIJYxr3IAB8AAAAAA==.Steb:BAAALgADCgMJAwAAAA==.Sterjariger:BAAALgAECgYJBgABLgAFFAMJAwAWAAAAAA==.',
Su='Sunari:BAAALgAECgMJBAAAAA==.Supermelon:BAABLgAECn8WAAIhAAcJXBHrCwBdAQAhAAcJXBHrCwBdAQAAAA==.',
Sw='Swenior:BAAALgADCgEJAQAAAA==.',
Sy='Sylvaeelor:BAAALgAFFAEJAQABLgAFFAQJDgAaAG4TAA==.Sylvanaria:BAABLgAECn89AAIRAAkJWya7AADJAwARAAkJWya7AADJAwAAAA==.Sylvanaris:BAAALgAECgYJEQAAAA==.Systyx:BAABLgAECn8bAAIeAAcJdx96RwC4AQAeAAcJdx96RwC4AQAAAA==.',
Ta='Takura:BAAALgAECgcJBwABLgAECgkJCwAWAAAAAA==.Talenel:BAAALgAECgQJBAAAAA==.Talyzien:BAAALgADCgYJBwAAAA==.',
Te='Tealan:BAACLgAFFH8GAAMJAAMJQQ9yGwDHAAAJAAMJQQ9yGwDHAAADAAEJRgK5XQAzAAAuAAQKfzAAAwMACQm0GCoRAEICAAMACQm0GCoRAEICAAkACAmpEukcAJ4BAAAA.Tealyn:BAAALgAECgUJBgAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAABLgAECn8lAAIFAAkJOiWGFAAAAwAFAAkJOiWGFAAAAwAAAA==.',
Th='Thaneer:BAAALgAECgYJBwAAAA==.Thanos:BAABLgAECn8dAAICAAYJ7Q6KpAA3AQACAAYJ7Q6KpAA3AQAAAA==.Thebadmage:BAAALgAECgcJBAAAAA==.Throstmok:BAACLgAFFH8GAAIOAAMJDA5jIwCmAAAOAAMJDA5jIwCmAAAuAAQKfzcAAg4ACQm3HuYHAIYCAA4ACQm3HuYHAIYCAAAA.Thràll:BAAALgAECgUJBQAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJFAAlALwhAA==.Thumbalina:BAAALgAECgYJEQAAAA==.',
To='Totemtuggér:BAAALgADCgIJAgAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trampstãmp:BAAALgAECgIJAgAAAA==.Trout:BAAALgADCgYJDAABLgAECgYJCgAWAAAAAA==.Trovikk:BAAALgADCgUJBgAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwAWAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgYJBwAAAA==.',
Ul='Ulfast:BAABLgAECn8lAAIgAAgJSh4/FwASAgAgAAgJSh4/FwASAgAAAA==.',
Va='Valarios:BAAALgAECgYJCgAAAA==.Vannhellsing:BAABLgAECn8mAAIFAAgJCwgdjQA2AQAFAAgJCwgdjQA2AQAAAA==.Vanyel:BAABLgAECn9IAAIGAAkJcxXBOgAXAgAGAAkJcxXBOgAXAgAAAA==.Vaudorka:BAABLgAECn8cAAIEAAkJIx7ZAgBsAgAEAAkJIx7ZAgBsAgAAAA==.',
Ve='Vecna:BAAALgADCgMJAwABLgAECgYJCAAWAAAAAA==.Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAABLgAECn83AAMcAAkJ+BSTEABJAgAcAAkJVxSTEABJAgAMAAcJzghySAAXAQAAAA==.Vemal:BAABLgAECn8sAAIKAAkJ1Rb4IQBGAgAKAAkJ1Rb4IQBGAgAAAA==.',
Vo='Vociferoy:BAACLgAFFH8HAAIKAAIJ/BfWYwCiAAAKAAIJ/BfWYwCiAAAuAAQKf0MAAgoACQl9IasLAOMCAAoACQl9IasLAOMCAAAA.Voidsteffan:BAABLgAECn8hAAMdAAcJuxmOBwC9AQAdAAcJuxmOBwC9AQAeAAQJjw4iwQDXAAAAAA==.',
Vr='Vryadox:BAAALgAFFAIJAgABLgAFFAQJDQAeAGwdAA==.',
Vv='Vv:BAACLgAFFH8zAAIHAAgJwiQdAQAIAwAHAAgJwiQdAQAIAwAuAAQKfzQAAgcACQm1JucAANoDAAcACQm1JucAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wr='Wry:BAAALgAECgMJAwAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
['Wá']='Wárranpeace:BAAALgADCgMJAwAAAA==.',
Xa='Xalmo:BAAALgADCgUJBQAAAA==.Xalzi:BAAALgADCggJCQABLgAECgcJFAARAHwVAA==.',
Xi='Xingwong:BAABLgAECn85AAIjAAgJnCX7AwDwAgAjAAgJnCX7AwDwAgAAAA==.',
Za='Zannytoes:BAABLgAECn8mAAMUAAkJpRDXKAC2AQAUAAkJpRDXKAC2AQALAAEJLxHajAAxAAAAAA==.',
Ze='Zead:BAAALgAECgEJAwAAAA==.Zerana:BAACLgAFFH8GAAIdAAMJwASlDAC0AAAdAAMJwASlDAC0AAAuAAQKfxUAAh0ACQnlCwoMAGEBAB0ACQnlCwoMAGEBAAAA.Zeriea:BAAALgADCgEJAQAAAA==.Zevtra:BAAALgADCgEJAQAAAA==.',
Zi='Zie:BAABLgAECn9HAAIBAAkJehjZDwBCAgABAAkJehjZDwBCAgAAAA==.Zikren:BAAALgAECgkJCQAAAA==.',
Zs='Zsinj:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðonkle:BAABLgAECn8TAAIHAAgJmByoJwAXAgAHAAgJmByoJwAXAgAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAACLgAFFH8XAAIPAAUJMyQ9CQCcAQAPAAUJMyQ9CQCcAQAuAAQKfxoAAg8ACQkrHmYVADECAA8ACQkrHmYVADECAAAA.',
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
