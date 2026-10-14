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

local lookup = {'Unknown-Unknown','Priest-Holy','Priest-Shadow','Mage-Arcane','Mage-Frost','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Feral','Paladin-Protection','DeathKnight-Blood','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Paladin-Holy','Druid-Restoration','Paladin-Retribution','Monk-Brewmaster','Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','DeathKnight-Unholy','Druid-Guardian','DemonHunter-Vengeance','DemonHunter-Devourer','DeathKnight-Frost','Warrior-Arms','Hunter-Survival','Shaman-Enhancement','Warrior-Fury','Priest-Discipline','Evoker-Augmentation','Rogue-Assassination','Warlock-Affliction','DemonHunter-Havoc','Druid-Balance',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abelladanger:BAAANQAECgUICAAAAA==.',
Ad='Addilyn:BAAANQAECgYIEQAAAA==.',
Ag='Agntclappers:BAAANQADCgUJBQAAAA==.Agonyzê:BAAANQADCgQIBAAAAA==.',
Ah='Ahminous:BAAANQAECgYIEQAAAA==.Ahroo:BAAANQAECgcIEQABNQAECggIAgABAAAAAQ==.Ahrue:BAAANQAECggIAgAAAQ==.',
Ai='Aikanaro:BAAANQAECgUICgAAAA==.Airc:BAAANQAECgQIDwAAAA==.',
Aj='Ajanti:BAAANQAECgQIAwAAAA==.',
Al='Alfster:BAAANQAECgMIBAABNQAECgUIEAABAAAAAA==.Allanor:BAAANQADCgEIAQAAAA==.Alliam:BAAANQADCgUIDQAAAA==.',
An='Ancalagon:BAABNQAECn8YAAMCAAgKJxWBbwDKAQACAAYKlhaBbwDKAQADAAYK+gxGPwAwAQAAAA==.',
Ar='Argeikeranos:BAABNQAECn8wAAMEAAkKEiBtSQDvAgAEAAkKax9tSQDvAgAFAAIKmx8aKACxAAAAAA==.',
As='Asystole:BAAANQAECgEIAgAAAA==.',
At='Atheish:BAAANQADCgcICAAAAA==.Atiko:BAAANQADCgQIBAABNQAFFAMICAAGAKEXAA==.Atomicrednax:BAACNQAFFH8bAAMHAAcKmiQgAwBdAgAHAAYKryUgAwBdAgAIAAEKRSAkLgBiAAA1AAQKfzgAAwcACQoZJn0NAAUDAAcACQrFJX0NAAUDAAgAAQrwJNBEAU0AAAAA.',
Au='Augtoberfest:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Ay='Ayisen:BAAANQAECgEIAQAAAA==.',
Ba='Ballsmonk:BAAANQAECgUIBQAAAA==.Ballsofury:BAACNQAFFH8FAAIJAAIKaCZnAgDlAAAJAAIKaCZnAgDlAAA1AAQKfx8AAgkACQrpJiAAABMEAAkACQrpJiAAABMEAAAA.Baptism:BAAANQAECgIIAwAAAA==.Battousaiha:BAAANQAECgYIEwAAAA==.',
Be='Beezelbubba:BAAANQABCgIIAgAAAA==.',
Bi='Bigmustard:BAAANQADCggICAABNQAFFAcIGQAKAPwkAA==.',
Bl='Blackcoffee:BAAANQAECgQIBwAAAA==.Blippi:BAAANQAECgEIAQABNQABCgQIBAABAAAAAA==.Bloatlord:BAAANQABCgIIAgAAAA==.',
Bo='Boojum:BAAANQAECgEIAwAAAA==.Bortikus:BAAANQADCgYIBwABNQAECggIHQALAOsbAA==.',
Bu='Burney:BAABNQAECn8qAAMMAAgK8B86DADfAgAMAAgK8B86DADfAgANAAcKIRxREwAXAgAAAA==.Burnnotice:BAAANQADCgQIBAAAAA==.Busadinn:BAAANQAECgYIEgAAAA==.',
['Bò']='Bònesaw:BAACNQAFFH8FAAIOAAIKtCDlBAC/AAAOAAIKtCDlBAC/AAA1AAQKfywAAg4ACQqpI0cCAJQDAA4ACQqpI0cCAJQDAAAA.',
Ca='Calibrium:BAAANQAECgYIDgAAAA==.Carll:BAABNQAECn8tAAIPAAkKRR1rHgD2AgAPAAkKRR1rHgD2AgAAAA==.',
Ch='Chister:BAABNQAECn8XAAIQAAgKuwxlMQCLAQAQAAgKuwxlMQCLAQAAAA==.Cholomonga:BAAANQAECgYICQABNQAFFAcIGQAGAAMXAA==.Churchill:BAAANQADCgUIBQABNQAFFAUIEgARAFQiAA==.',
Co='Colisto:BAAANQADCgQIBAAAAA==.',
Cr='Crazedx:BAABNQAECn8VAAMSAAgKciMjBQASAwASAAgKNyMjBQASAwATAAMKAhqvSADXAAAAAA==.Criotor:BAAANQADCgcIBgAAAA==.',
Cy='Cyral:BAAANQAECgQIBgAAAA==.',
Da='Daddy:BAABNQAECn8rAAMUAAkK1SBkAgA7AwAUAAkKWBtkAgA7AwAVAAgKmhVNWQBHAgAAAA==.Daito:BAAANQADCgQIBwAAAA==.Darig:BAAANQAECgIIBAAAAA==.Daryun:BAAANQAECgEIAQABNQAECgUICgABAAAAAA==.',
De='Deathsrain:BAAANQADCgIIAgAAAA==.Decimas:BAAANQAECgUIBQAAAA==.Decimez:BAAANQAECgYIEgAAAA==.Decimock:BAABNQAECn8XAAIUAAgK6h6rBgCfAgAUAAgK6h6rBgCfAgAAAA==.',
Di='Digerati:BAAANQADCgUIBQAAAA==.Dingiswayo:BAABNQAECn8iAAITAAkKqBX+HQBAAgATAAkKqBX+HQBAAgAAAA==.Dingybing:BAAANQAECgUIDAAAAA==.Dishwasherx:BAAANQAECgMIBgAAAA==.Dizan:BAAANQAECgMICAABNQAECgUICgABAAAAAA==.',
Dp='Dpitis:BAABNQAECn8tAAMDAAkKxB2WDwD5AgADAAkKxB2WDwD5AgACAAUKWxyigQCOAQAAAA==.',
Dr='Dragonflyy:BAAANQADCgQICQAAAA==.Draks:BAAANQAECgEJAgAAAA==.Drinkyds:BAABNQAECn8bAAIWAAkKLiEEJADUAgAWAAkKLiEEJADUAgAAAA==.',
Er='Eriebus:BAAANQAECgYIEQAAAA==.Erona:BAABNQAECn8aAAIWAAYKPhwYbADDAQAWAAYKPhwYbADDAQAAAA==.',
Es='Escorpiøn:BAAANQAECgEIAQAAAA==.',
Ev='Evenstar:BAAANQAECgcIBwAAAA==.',
Ex='Extendo:BAABNQAECn8VAAIXAAcKzRC9awBgAQAXAAcKzRC9awBgAQAAAA==.',
Fa='Falkor:BAAANQADCggIDgABNQAECgkJLQADAMQdAA==.Fatshock:BAAANQADCggIEAAAAA==.',
Fe='Fearbum:BAABNQAECn8VAAIUAAgKhA2AEgDfAQAUAAgKhA2AEgDfAQAAAA==.Felagain:BAAANQAECgQIBgAAAA==.Ferdinane:BAAANQAECgYIEwAAAA==.',
Fi='Fidgety:BAAANQADCggIEQAAAA==.',
Fl='Flankshot:BAACNQAFFH8FAAIFAAIKLwlVCQCDAAAFAAIKLwlVCQCDAAA1AAQKfyoAAgUACQpVGaAFALMCAAUACQpVGaAFALMCAAAA.',
Fo='Foops:BAACNQAFFH8OAAMFAAUKkBfNAACqAQAFAAUKkBfNAACqAQAEAAEKAABgZgA3AAA1AAQKfx0AAgUACQoXHEEHAHwCAAUACQoXHEEHAHwCAAAA.Foopsadin:BAAANQAECgMICAABNQAFFAUIDgAFAJAXAA==.Footloose:BAAANQAECgEIAgAAAA==.',
Fr='Freaky:BAAANQAECgEIAQAAAA==.',
Fu='Fumìn:BAAANQAECgUICQAAAA==.',
Ga='Gallena:BAAANQAECgEIAQAAAA==.Gassommelier:BAAANQAECgEIAwAAAA==.',
Ge='Geezuss:BAAANQAECgQIBAAAAA==.Genohbreaker:BAAANQAECgUIEgAAAA==.Getrkt:BAABNQAECn8XAAIRAAgKrAmNwwCPAQARAAgKrAmNwwCPAQAAAA==.',
Gi='Gimblie:BAABNQAECn8ZAAICAAcKMxr6WwAKAgACAAcKMxr6WwAKAgAAAA==.Gimermonty:BAAANQAECgcIEwAAAA==.Gimixx:BAAANQAECggIEgAAAA==.',
Gl='Gladrielle:BAAANQAECgEIAQAAAA==.Glatzkaus:BAAANQAECgYICgAAAA==.Glockcena:BAAANQAECgEIBAAAAA==.',
Gn='Gnolom:BAAANQADCgYIBgAAAA==.Gnomedk:BAAANQAECgEIAwAAAA==.',
Go='Gothegg:BAAANQAECgEIAQAAAA==.',
Gr='Gripen:BAAANQAECgEIAgAAAA==.Gronk:BAAANQADCggICwAAAA==.',
Gu='Guldanshower:BAAANQAECgIIAgAAAA==.Gutterfire:BAAANQAECgEIAgAAAA==.',
Ha='Hakal:BAABNQAECn8qAAIYAAgKlCNoBwANAwAYAAgKlCNoBwANAwAAAA==.Halvor:BAAANQAECgIIAgAAAA==.Hangbladz:BAABNQAECn8WAAMZAAcKDhFGGgAPAQAaAAYK1BAWOgBwAQAZAAYKsAtGGgAPAQAAAA==.Hanita:BAAANQAECgMIAwAAAA==.Hardwarë:BAABNQAECn8WAAMbAAYKkgloYAAbAQAbAAYKkgloYAAbAQAXAAIKEgIX4QAwAAAAAA==.Hattshepsut:BAAANQADCgQIBAAAAA==.',
He='Healinghands:BAAANQAECgYIEAAAAA==.Hellz:BAABNQAECn8uAAIOAAkKHBujCQCtAgAOAAkKHBujCQCtAgAAAA==.',
Hu='Hudochar:BAAANQADCgMIAwAAAA==.Hukdemon:BAAANQAECgYIEQAAAA==.',
Ic='Iceandfire:BAAANQAECgIIAwAAAA==.',
Ig='Igneel:BAABNQAECn8UAAIcAAcK8Rb9iwD6AQAcAAcK8Rb9iwD6AQABNQAECgkJLQADAMQdAA==.',
In='Inviteme:BAAANQAECgIIAwAAAA==.',
Iw='Iwillsaverap:BAAANQADCggICAAAAA==.',
Ja='Jaelá:BAAANQAECgEIAQABNQAECgQIAwABAAAAAA==.',
Je='Jessick:BAAANQAECgIIAgABNQAFFAIIBQAOALQgAA==.',
Jh='Jhamin:BAACNQAFFH8IAAIGAAMKoRfEGgDnAAAGAAMKoRfEGgDnAAA1AAQKfyYAAwYACQr2GqI2AJkCAAYACQr2GqI2AJkCABYAAwroBnD0AHwAAAAA.',
Jo='Joss:BAAANQAECgMIBAAAAA==.',
Ju='Jubei:BAAANQADCgYIDAAAAA==.Jubeiskyfang:BAAANQAECggICAAAAA==.Julkaal:BAAANQADCgUIBQAAAA==.',
Jy='Jynken:BAAANQAECgEIAgABNQAECgUICgABAAAAAA==.',
Ka='Kaedrelyn:BAAANQAECgUIDAAAAA==.Kageyuki:BAEANQAECgEIAQABNQAECggIFgAbAH4MAA==.',
Ke='Kennyman:BAAANQAECgEIAQAAAA==.Ketheric:BAAANQADCgMIAwAAAA==.',
Ki='Kindinos:BAAANQAECgEIAgAAAA==.',
Kl='Klickyy:BAAANQAECgQICAABNQAFFAYICAARAHIWAA==.Kllcky:BAACNQAFFH8IAAIRAAYKchaKBAAYAgARAAYKchaKBAAYAgA1AAQKfywAAxEACQr+JvgCAOYDABEACQr+JvgCAOYDAA8AAQrMCEIdATUAAAAA.',
Kr='Kraun:BAABNQAECn8fAAIIAAcKkSQxMADaAgAIAAcKkSQxMADaAgAAAA==.Kroo:BAABNQAECn8mAAITAAkKyRPhIQAXAgATAAkKyRPhIQAXAgAAAA==.',
Ku='Kurnon:BAAANQAECgQIBQABNQAECgUIBgABAAAAAA==.',
Ky='Kyi:BAABNQAECn8mAAITAAkKpRaRHgA6AgATAAkKpRaRHgA6AgAAAA==.',
La='Lammlock:BAAANQAECgYICAAAAA==.Landar:BAABNQAECn8lAAIQAAkKSRYtHABQAgAQAAkKSRYtHABQAgAAAA==.Lazurin:BAAANQADCggIEAAAAA==.',
Le='Lebronsamdi:BAAANQADCggICAAAAA==.',
Li='Liara:BAABNQAECn8gAAIdAAkKHhMmBQB1AgAdAAkKHhMmBQB1AgAAAA==.',
Lo='Lockonyou:BAABNQAECn8VAAIVAAcK6gfevwBHAQAVAAcK6gfevwBHAQAAAA==.Losthack:BAABNQAECn8WAAIPAAcKRSSwIwDaAgAPAAcKRSSwIwDaAgAAAA==.',
Lt='Ltfirebomb:BAAANQADCgIIAQAAAA==.',
Lu='Lutherhuss:BAAANQAECgcIEgAAAA==.',
Ma='Mahra:BAAANQAECgYIEQAAAA==.Manchasone:BAABNQAECn8VAAIRAAcKKiXfOgDjAgARAAcKKiXfOgDjAgAAAA==.Mangreese:BAABNQAECn8UAAIeAAcK0ArZHACRAQAeAAcK0ArZHACRAQAAAA==.',
Me='Meekseek:BAAANQAECggIDAAAAA==.',
Mi='Miahealifa:BAABNQAECn8VAAMCAAcKNhXYcQDDAQACAAcKNhXYcQDDAQADAAEKtgOxgAAnAAAAAA==.Miasma:BAAANQAECgUIEgAAAA==.Micaiah:BAAANQAECgQICQAAAA==.Mistabubbles:BAAANQAECgcIDwAAAA==.',
Mk='Mk:BAAANQAECgcICgAAAA==.',
Mo='Mochi:BAAANQAECgEIAgAAAA==.Mograinez:BAACNQAFFH8bAAMXAAcKoyYkAADuAgAXAAcKoyYkAADuAgALAAEKAAAnNQAnAAA1AAQKfxsAAhcACQr2JtANAEkDABcACQr2JtANAEkDAAAA.Moosebreath:BAAANQAFFAEIAQAAAA==.',
Ne='Necrussy:BAAANQAECgEIAQAAAA==.Nekrohealia:BAAANQAECgcIDwAAAA==.Neteyam:BAAANQAECgQIAgAAAA==.',
No='Nogitsune:BAAANQADCgEIAQAAAA==.Noluck:BAAANQAECgEIAgAAAA==.Norolock:BAAANQAECgYIEQAAAA==.',
Nu='Nuovis:BAAANQAECgEIAQAAAA==.',
['Nã']='Nãrcissus:BAAANQAECgQIBwABNQAFFAYICAARAHIWAA==.',
Og='Oghlin:BAABNQAECn8WAAITAAgKCB/qFgCSAgATAAgKCB/qFgCSAgAAAA==.',
Oh='Ohwarrior:BAAANQAECgQIBgAAAA==.',
Ol='Oldshotz:BAABNQAECn8WAAIIAAYKURN6uQCMAQAIAAYKURN6uQCMAQAAAA==.',
Om='Omgsteak:BAAANQAECgUIEgAAAA==.',
On='Onlybusa:BAAANQAECgUICAAAAA==.',
Or='Orcofwar:BAAANQADCgYIBgAAAA==.',
Pa='Palidan:BAAANQAECgcIDgAAAA==.Panzerwolf:BAECNQAFFH8VAAIOAAcKyiMWAADrAgAOAAcKyiMWAADrAgA1AAQKf0IABA4ACQoXJskBAKoDAA4ACQoXJskBAKoDAB8ACQooH4EDAB0DABwACArPGr9kAF0CAAAA.Papilock:BAAANQAECgEIAQAAAA==.Parsnip:BAAANQAECgQICgAAAA==.',
Pr='Pray:BAAANQAECgUIBQAAAA==.Prayforme:BAABNQAECn8wAAMgAAkKsiKXAQAwAwAgAAgKMCOXAQAwAwACAAYKHhlxcADHAQAAAA==.Prugaru:BAAANQADCgYIBgAAAA==.',
Ps='Psilocybic:BAABNQAECn8hAAMWAAkKEg23ZwDSAQAWAAkKEg23ZwDSAQAGAAEKpgWOVgEeAAAAAA==.Psychopompos:BAAANQADCggICAABNQAECgkJMAAEABIgAA==.',
Qr='Qreigns:BAAANQAECgYICgAAAA==.',
Qw='Qweh:BAAANQAECgUICwAAAA==.',
Ra='Raenia:BAAANQADCgUIBQAAAA==.Rahnko:BAAANQADCgMIAwAAAA==.Rakkasei:BAABNQAECn8gAAMNAAkKvRY3EABSAgANAAkKpBI3EABSAgAhAAYK2herCgC/AQAAAA==.Rangol:BAAANQADCgYIBgAAAA==.Ravenoth:BAABNQAECn8mAAIiAAcKZx5GJgBWAgAiAAcKZx5GJgBWAgAAAA==.Razkal:BAABNQAECn8WAAIIAAcKOxgXeQAZAgAIAAcKOxgXeQAZAgAAAA==.Razpal:BAAANQAECgMIBAAAAA==.',
Re='Revirginator:BAAANQAECgQIBgAAAA==.',
Ri='Rimreaper:BAAANQAECgUIDQAAAA==.',
Rn='Rngesus:BAACNQAFFH8FAAIVAAMKXQZ4JgDRAAAVAAMKXQZ4JgDRAAA1AAQKfygAAxUACQoRHg0tAM8CABUACQoBHA0tAM8CACMAAgorEQUfAH4AAAE1AAUUAwgIAAYAoRcA.',
Ru='Ruffle:BAAANQAECgQIBQAAAA==.Runie:BAEANQADCgQIBAABNQAFFAYIGQAcABMZAA==.Rushem:BAAANQAECgYIEAAAAA==.',
Ry='Ryft:BAAANQADCgUIBQAAAA==.',
['Rà']='Ràvenoth:BAABNQAECn8cAAMVAAkKqRuPIAD/AgAVAAkKqRuPIAD/AgAUAAEKoRF/cQA9AAAAAA==.Ràyà:BAAANQADCgQIBAAAAA==.',
Sa='Saenen:BAABNQAECn8aAAIJAAcK/w3RFgCIAQAJAAcK/w3RFgCIAQAAAA==.',
Sc='Scorchi:BAAANQAECgQJCAAAAA==.',
Se='Serenity:BAAANQAECgEIAQAAAA==.Seseria:BAABNQAECn8lAAIPAAkK9BaXNwCDAgAPAAkK9BaXNwCDAgAAAA==.Sevinofnine:BAAANQAECgUIDAAAAA==.',
Sh='Shadowsong:BAAANQAECgcIDwAAAA==.Shaithis:BAAANQAECgEIAQAAAA==.Shamantics:BAAANQADCgcICwABNQADCggIDwABAAAAAA==.Shanic:BAAANQAECgYIEQAAAA==.Shavedcat:BAAANQADCgMIAwAAAA==.Shinnylock:BAAANQADCgEIAQAAAA==.Shocktart:BAAANQAECgIIAgAAAA==.',
Si='Siheal:BAAANQAECgMIBQAAAA==.',
Sl='Sleeping:BAAANQAECgEIAQAAAA==.Sliceanddice:BAAANQADCgIIAgAAAA==.',
Sn='Snipymagus:BAAANQAECgQIBQABNQAFFAcIGQAGAAMXAA==.Snipyterror:BAACNQAFFH8ZAAMGAAcKAxfgCQDJAQAGAAUKJBngCQDJAQAWAAMKlg3SFgDqAAA1AAQKfygAAwYACQpDI18NAHwDAAYACQpDI18NAHwDABYAAgpEB9ICAV0AAAAA.',
So='Socraates:BAAANQABCgQIAgAAAA==.Solarkami:BAAANQAECgcIAgAAAA==.',
Sp='Spacejam:BAAANQADCgYIFQAAAA==.Specimenb:BAAANQAECggIDAAAAA==.Spirallidan:BAABNQAECn8lAAMkAAkKyxf+IQCHAgAkAAkKyxf+IQCHAgAaAAQKZwqGVAC5AAAAAA==.',
St='Staticsrexar:BAABNQAECn8aAAQIAAcK/xNIlwDVAQAIAAcK/xNIlwDVAQAdAAEKJQZ8EgA9AAAHAAEKAAAdlwAnAAAAAA==.Stayk:BAAANQADCgcIDQAAAA==.Stepbro:BAAANQAECgIIAgABNQAECgIIAwABAAAAAA==.Stinksauce:BAABNQAECn8gAAQMAAkKNxdBEgCHAgAMAAkKNxdBEgCHAgAhAAUK8xvcCwCbAQANAAQKyA4sJwD3AAAAAA==.Strokntotem:BAAANQAECgQICAAAAA==.',
Su='Superchunk:BAAANQAECgIIBAAAAA==.Sutra:BAAANQAECgcIEwAAAA==.',
Sy='Sylmarillion:BAAANQAECgUIBgAAAA==.',
Ta='Talgulen:BAABNQAECn8jAAINAAgKMhnUDQCBAgANAAgKMhnUDQCBAgAAAA==.Tarquinius:BAAANQAECgUJDwAAAA==.Tasahof:BAAANQAECggIAQAAAA==.Taxii:BAAANQAECgQICAABNQAECgkJKAAcAHwiAA==.Taynte:BAAANQAECgcIDgAAAA==.',
Th='Thedarkseed:BAAANQADCgYIDAAAAA==.Theoeicke:BAABNQAECn8WAAIVAAcK4QmWqQB7AQAVAAcK4QmWqQB7AQABNQAECgkJJgATAKUWAA==.Thrag:BAAANQAECgIIAwABNQAECgUICgABAAAAAA==.',
Ti='Tifferny:BAAANQADCgMIAwAAAA==.Tiffèrny:BAAANQAECgEIAQAAAA==.',
To='Tone:BAAANQAECggIDAAAAA==.Torokami:BAAANQAECggIBgAAAA==.Toronoro:BAAANQAECggICQAAAA==.Toroshin:BAAANQAECggIAgAAAA==.Toroshinu:BAAANQAECggIAgAAAA==.Torotatsu:BAAANQAECgIIAwAAAA==.Totemlycool:BAAANQAECgUIBQABNQAECgkJJgATAMkTAA==.',
Tr='Traice:BAAANQADCgQIBAAAAA==.Trappress:BAABNQAECn8fAAIIAAkKDhXzQgCgAgAIAAkKDhXzQgCgAgAAAA==.Treehuggër:BAABNQAECn8ZAAMQAAcKHhSULgCiAQAQAAcKHhSULgCiAQAlAAIKnQgepABNAAAAAA==.Trelia:BAAANQAECgEIAQAAAA==.Trogkin:BAABNQAECn8bAAIlAAgK2xixLABzAgAlAAgK2xixLABzAgABNQAFFAcIFgAHAE8cAA==.',
Ty='Tyrith:BAABNQAECn8eAAIcAAkKcB01KQATAwAcAAkKcB01KQATAwAAAA==.',
Ug='Ugotgotpal:BAABNQAECn8XAAIRAAgKDAgyzwB3AQARAAgKDAgyzwB3AQAAAA==.',
Ul='Ulazain:BAABNQAECn8jAAIfAAgKOBq1BgCXAgAfAAgKOBq1BgCXAgAAAA==.',
Um='Umadcuzbad:BAAANQADCgcICQAAAA==.',
Us='Usdaprime:BAAANQAECgcIEgAAAA==.',
Va='Vaas:BAAANQAECgYICwAAAA==.Vaporeön:BAAANQAECgcIDQAAAA==.Varrasha:BAAANQABCgIIAgAAAA==.',
Ve='Verric:BAAANQADCgEIAQAAAA==.',
Vi='Viì:BAABNQAECn8aAAIRAAcKQA2kygCAAQARAAcKQA2kygCAAQAAAA==.',
Vo='Voidarella:BAAANQABCgMIAwABNQAECgkJKAARAAobAA==.',
['Vè']='Vèx:BAABNQAECn8uAAIcAAkKfB+PMgDzAgAcAAkKfB+PMgDzAgAAAA==.',
Wa='Waronyou:BAAANQADCgcIDgABNQAECgcIFQAVAOoHAA==.Watlas:BAAANQAECgUIBwABNQAECgkJKQAXAIAlAA==.',
Xa='Xavia:BAAANQAECgUIEgAAAA==.',
Yu='Yunaraa:BAAANQAECgIJAwABNQAECgkJHwAIAA4VAA==.',
Yv='Yvana:BAAANQAECgEIAQAAAA==.',
Ze='Zephyrpriest:BAAANQAECgMICAABNQAFFAcIGQAlAAkkAA==.',
Zo='Zombies:BAAANQAECgYIEAAAAA==.',
Zu='Zugmaster:BAABNQAECn8rAAIiAAgKtRkaJABjAgAiAAgKtRkaJABjAgAAAA==.Zulureus:BAAANQAECgEIAQAAAA==.',
Zy='Zynn:BAAANQAECgEJAgABNQABCgQIBAABAAAAAA==.',
Zz='Zzephyrdruid:BAACNQAFFH8ZAAIlAAcKCSS2AQDUAgAlAAcKCSS2AQDUAgA1AAQKfxwAAiUACQrpJWISADMDACUACQrpJWISADMDAAAA.Zzephyrmage:BAAANQAECgMIBQABNQAFFAcIGQAlAAkkAA==.',
['Çä']='Çärvé:BAAANQADCgIIAgAAAA==.',
['Ôä']='Ôäk:BAAANQADCgUIBQABNQAECgUIDwABAAAAAA==.',
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
