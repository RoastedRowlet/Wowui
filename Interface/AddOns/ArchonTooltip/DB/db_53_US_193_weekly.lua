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

local lookup = {'Unknown-Unknown','Mage-Arcane','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Feral','Paladin-Protection','Evoker-Preservation','Warrior-Protection','Paladin-Holy','Paladin-Retribution','DeathKnight-Blood','Warlock-Destruction','Warlock-Demonology','Monk-Windwalker','Priest-Shadow','Priest-Holy','Shaman-Restoration','Mage-Frost','Druid-Guardian','Druid-Restoration','Hunter-Survival','DeathKnight-Unholy','Warrior-Fury','Warrior-Arms','Priest-Discipline','Evoker-Devastation','Rogue-Assassination','Warlock-Affliction','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Augmentation','Druid-Balance',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abelladanger:BAAANQAECgUIBwAAAA==.',
Ad='Addilyn:BAAANQAECgUICAAAAA==.',
Ag='Agntclappers:BAAANQADCgUJBQAAAA==.Agonyzê:BAAANQADCgQIBAAAAA==.',
Ah='Ahminous:BAAANQAECgUICAAAAA==.Ahroo:BAAANQAECgQIBgABNQAECggIAgABAAAAAQ==.Ahrue:BAAANQAECggIAgAAAQ==.',
Ai='Airc:BAAANQAECgIIAwAAAA==.',
Aj='Ajanti:BAAANQAECgMIAQAAAA==.',
Al='Alfster:BAAANQAECgMIAwABNQAECgUICgABAAAAAA==.Allanor:BAAANQADCgEIAQAAAA==.Alliam:BAAANQADCgUIDQAAAA==.',
An='Ancalagon:BAAANQAECgYIDwAAAA==.',
Ar='Argeikeranos:BAABNQAECoElAAICAAgKHCB/VgCpAgACAAgKHCB/VgCpAgAAAA==.',
As='Asystole:BAAANQADCgEIAQAAAA==.',
At='Atheish:BAAANQADCgcICAAAAA==.Atiko:BAAANQADCgQIBAABNQAECgkJIwADAK0aAA==.Atomicrednax:BAACNQAFFIEYAAMEAAcKJySgAQBwAgAEAAYKzSSgAQBwAgAFAAEKRSCqHgBmAAA1AAQKgSoAAwQACQqCJf8IACcDAAQACQpBJf8IACcDAAUAAQrwJBEJAU4AAAAA.',
Au='Augtoberfest:BAAANQAECgEIAQABNQAECgIIBAABAAAAAA==.',
Ay='Ayisen:BAAANQADCgYICgAAAA==.',
Ba='Ballsofury:BAABNQAECoEXAAIGAAgK2iZxAQCZAwAGAAgK2iZxAQCZAwAAAA==.Baptism:BAAANQAECgEIAQAAAA==.Battousaiha:BAAANQAECgUICQAAAA==.',
Be='Beezelbubba:BAAANQABCgIIAgAAAA==.',
Bi='Bigmustard:BAAANQADCggICAABNQAFFAYIEQAHAKYhAA==.',
Bl='Blackcoffee:BAAANQAECgQIBAAAAA==.Blippi:BAAANQADCgQIBgABNQABCgQIBAABAAAAAA==.Bloatlord:BAAANQABCgIIAgAAAA==.',
Bo='Boojum:BAAANQAECgEIAQAAAA==.Bortikus:BAAANQADCgMIAwABNQAECgIIAwABAAAAAA==.',
Bu='Burney:BAABNQAECoEbAAIIAAgK4B26DACzAgAIAAgK4B26DACzAgAAAA==.Burnnotice:BAAANQADCgQIBAAAAA==.Busadinn:BAAANQAECgQIBwAAAA==.',
['Bò']='Bònesaw:BAABNQAECoEfAAIJAAgKySGtBAD4AgAJAAgKySGtBAD4AgAAAA==.',
Ca='Calibrium:BAAANQAECgYIDQAAAA==.Carll:BAABNQAECoEfAAIKAAkK/BmoHQDNAgAKAAkK/BmoHQDNAgAAAA==.',
Ch='Chister:BAAANQAECgcIEQAAAA==.Cholomonga:BAAANQAECgQIBQABNQAFFAYIEQADAAYdAA==.Churchill:BAAANQADCgUIBQABNQAFFAQICQALAIwXAA==.',
Co='Colisto:BAAANQADCgQIBAAAAA==.',
Cr='Crazedx:BAAANQAECgcICAABNQAFFAUIBwAMANAWAA==.Criotor:BAAANQADCgcIBgAAAA==.',
Cy='Cyral:BAAANQAECgQIBgAAAA==.',
Da='Daddy:BAABNQAECoEpAAMNAAkKtyHaAQBFAwANAAkK/hzaAQBFAwAOAAgKphjVNwBwAgAAAA==.Daito:BAAANQADCgQIBwAAAA==.Darig:BAAANQAECgIIAgAAAA==.',
De='Deathsrain:BAAANQADCgIIAgAAAA==.Decimez:BAAANQAECgUICAAAAA==.Decimock:BAAANQAECgYIDgAAAA==.',
Di='Digerati:BAAANQADCgUIBQAAAA==.Dingiswayo:BAABNQAECoEbAAIPAAgKfxUtGwANAgAPAAgKfxUtGwANAgAAAA==.Dingybing:BAAANQAECgQIBgAAAA==.Dishwasherx:BAAANQAECgMIBgAAAA==.',
Dp='Dpitis:BAABNQAECoEgAAMQAAkKiRtEDwDNAgAQAAkKiRtEDwDNAgARAAUKWxyDYACbAQAAAA==.',
Dr='Dragonflyy:BAAANQADCgQIBAAAAA==.Draks:BAAANQAECgEJAgAAAA==.Drinkyds:BAABNQAECoEbAAISAAkKLiFLFQD2AgASAAkKLiFLFQD2AgAAAA==.',
Er='Eriebus:BAAANQAECgUICAAAAA==.Erona:BAAANQAECgUICwAAAA==.',
Es='Escorpiøn:BAAANQAECgEIAQAAAA==.',
Ex='Extendo:BAAANQAECgUIDgAAAA==.',
Fa='Falkor:BAAANQADCggIDgABNQAECgkJIAAQAIkbAA==.Fatshock:BAAANQADCggIEAAAAA==.',
Fe='Fearbum:BAAANQAECgcIDQAAAA==.Felagain:BAAANQAECgQIBAAAAA==.Ferdinane:BAAANQAECgUICwAAAA==.',
Fi='Fidgety:BAAANQADCggIEQAAAA==.',
Fl='Flankshot:BAABNQAECoEdAAITAAkKFxcxBQCCAgATAAkKFxcxBQCCAgAAAA==.',
Fo='Foops:BAACNQAFFIELAAMTAAUKBhhjAAChAQATAAUKBhhjAAChAQACAAEKpgHzTQA3AAA1AAQKgRkAAhMACQrfHKAEAJkCABMACQrfHKAEAJkCAAAA.Foopsadin:BAAANQAECgMIBgABNQAFFAUICwATAAYYAA==.Footloose:BAAANQAECgEIAgAAAA==.',
Ga='Gassommelier:BAAANQADCggICAAAAA==.',
Ge='Geezuss:BAAANQAECgQIBAAAAA==.Genohbreaker:BAAANQAECgUIDAAAAA==.Getrkt:BAAANQAECgUICAAAAA==.',
Gi='Gimblie:BAAANQAECgUIDwAAAA==.Gimermonty:BAAANQAECgcIEwAAAA==.Gimixx:BAAANQAECgUIDgAAAA==.',
Gl='Gladrielle:BAAANQADCggICgAAAA==.Glatzkaus:BAAANQAECgYICAAAAA==.Glockcena:BAAANQAECgEIAQAAAA==.',
Gn='Gnolom:BAAANQADCgYIBgAAAA==.Gnomedk:BAAANQAECgEIAQAAAA==.',
Go='Gothegg:BAAANQABCgUIBQAAAA==.',
Gr='Gripen:BAAANQABCggICwAAAA==.',
Gu='Guldanshower:BAAANQAECgIIAgAAAA==.Gutterfire:BAAANQABCgQIBAAAAA==.',
Ha='Hakal:BAABNQAECoEdAAIUAAgKZSBJBQDyAgAUAAgKZSBJBQDyAgAAAA==.Halvor:BAAANQAECgIIAgAAAA==.Hangbladz:BAAANQAECgYIEgAAAA==.Hanita:BAAANQAECgMIAwAAAA==.Hardwarë:BAAANQAECgUIDQAAAA==.',
He='Healinghands:BAAANQAECgQIBgAAAA==.Hellz:BAABNQAECoElAAIJAAgKwBunCAB4AgAJAAgKwBunCAB4AgAAAA==.',
Hu='Hudochar:BAAANQADCgMIAwAAAA==.Hukdemon:BAAANQAECgUICAAAAA==.',
Ic='Iceandfire:BAAANQAECgIIAwAAAA==.',
Ig='Igneel:BAAANQAECgYICwABNQAECgkJIAAQAIkbAA==.',
Iw='Iwillsaverap:BAAANQADCggICAAAAA==.',
Ja='Jaelá:BAAANQADCggICAABNQAECgMIAQABAAAAAA==.',
Je='Jessick:BAAANQAECgIIAgABNQAECggIHwAJAMkhAA==.',
Jh='Jhamin:BAABNQAECoEjAAMDAAkKrRqJJwCpAgADAAkKrRqJJwCpAgASAAMK6AbUygB9AAAAAA==.',
Jo='Joss:BAAANQAECgMIBAAAAA==.',
Ju='Jubei:BAAANQADCgYIDAAAAA==.Jubeiskyfang:BAAANQAECggICAAAAA==.Julkaal:BAAANQADCgUIBQAAAA==.',
Ka='Kaedrelyn:BAAANQAECgIIAgAAAA==.Kageyuki:BAEANQAECgEIAQABNQAECgkJIAAFANsVAA==.',
Ke='Kennyman:BAAANQADCgQIBAAAAA==.Ketheric:BAAANQADCgMIAwAAAA==.',
Ki='Kindinos:BAAANQADCggIHgAAAA==.',
Kl='Klickyy:BAAANQAECgMIAwABNQAECgkJJwALAPImAA==.Kllcky:BAABNQAECoEnAAILAAkK8ibkAAD+AwALAAkK8ibkAAD+AwAAAA==.',
Kr='Kraun:BAAANQAECggIEQAAAA==.Kroo:BAABNQAECoEgAAIPAAgK4BOPHAD7AQAPAAgK4BOPHAD7AQAAAA==.',
Ku='Kurnon:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.',
Ky='Kyi:BAABNQAECoEZAAIPAAgKaxYwGwANAgAPAAgKaxYwGwANAgAAAA==.',
La='Lammlock:BAAANQAECgYICAAAAA==.Landar:BAABNQAECoEeAAIVAAkKHRZjEwBtAgAVAAkKHRZjEwBtAgAAAA==.Lazurin:BAAANQADCggIEAAAAA==.',
Le='Lebronsamdi:BAAANQADCggICAAAAA==.',
Li='Liara:BAABNQAECoEYAAIWAAgKPBErBQAoAgAWAAgKPBErBQAoAgAAAA==.',
Lo='Lockonyou:BAABNQAECoEVAAIOAAcK2gfZjwBaAQAOAAcK2gfZjwBaAQAAAA==.Losthack:BAAANQAECgUICwAAAA==.',
Lt='Ltfirebomb:BAAANQADCgIIAQAAAA==.',
Lu='Lutherhuss:BAAANQAECgYJCgAAAA==.',
Ma='Mahra:BAAANQAECgYIEAAAAA==.Manchasone:BAAANQAECggICAAAAA==.Mangreese:BAAANQAECgcJDQAAAA==.',
Me='Meekseek:BAAANQAECgcICgAAAA==.',
Mi='Miahealifa:BAAANQAECgYIDAAAAA==.Miasma:BAAANQAECgUIDQAAAA==.Micaiah:BAAANQAECgMIAwAAAA==.Mistabubbles:BAAANQAECgYICAAAAA==.',
Mk='Mk:BAAANQAECgQIBAAAAA==.',
Mo='Mochi:BAAANQABCgIIAgAAAA==.Mograinez:BAACNQAFFIEYAAMXAAcKiCYLAADiAgAXAAcKiCYLAADiAgAMAAEKMA6nJwAqAAA1AAQKgRkAAhcACQr1JqoFAIMDABcACQr1JqoFAIMDAAAA.Moosebreath:BAAANQAFFAEIAQAAAA==.',
Ne='Necrussy:BAAANQADCgIIAgAAAA==.Nekrohealia:BAAANQAECgcIBwAAAA==.Neteyam:BAAANQADCgYIBgAAAA==.',
No='Nogitsune:BAAANQADCgEIAQAAAA==.Norolock:BAAANQAECgUICAAAAA==.',
Nu='Nuovis:BAAANQADCgYIBgAAAA==.',
['Nã']='Nãrcissus:BAAANQAECgIIAgABNQAECgkJJwALAPImAA==.',
Og='Oghlin:BAAANQAECgcICwAAAA==.',
Oh='Ohwarrior:BAAANQAECgQIBAAAAA==.',
Ol='Oldshotz:BAAANQAECgUIEAAAAA==.',
Om='Omgsteak:BAAANQAECgUICgAAAA==.',
On='Onlybusa:BAAANQADCgIIAgAAAA==.',
Pa='Palidan:BAAANQAECgQIBAAAAA==.Panzerwolf:BAECNQAFFIESAAIJAAYKZyUaAACWAgAJAAYKZyUaAACWAgA1AAQKgTYABAkACQolJrkAAMkDAAkACQolJrkAAMkDABgABwoNHusFAGMCABkABwqrG65nAA4CAAAA.Parsnip:BAAANQAECgQICAAAAA==.',
Pr='Pray:BAAANQAECgMIAwAAAA==.Prayforme:BAABNQAECoEiAAIaAAgKwSFIAQAnAwAaAAgKwSFIAQAnAwAAAA==.Prugaru:BAAANQADCgYIBgAAAA==.',
Ps='Psilocybic:BAABNQAECoEcAAISAAcKoA/6YQCRAQASAAcKoA/6YQCRAQAAAA==.Psychopompos:BAAANQADCggICAABNQAECggIJQACABwgAA==.',
Qr='Qreigns:BAAANQAECgEIAQAAAA==.',
Qw='Qweh:BAAANQAECgMIBgAAAA==.',
Ra='Raenia:BAAANQADCgUIBQAAAA==.Rahnko:BAAANQADCgMIAwAAAA==.Rakkasei:BAABNQAECoEYAAIbAAkKRxMbDgBFAgAbAAkKRxMbDgBFAgAAAA==.Rangol:BAAANQADCgYIBgAAAA==.Ravenoth:BAABNQAECoEdAAIcAAcK/RwlHABHAgAcAAcK/RwlHABHAgAAAA==.Razkal:BAAANQAECgYIDwAAAA==.Razpal:BAAANQAECgMIAwAAAA==.',
Re='Revirginator:BAAANQAECgEIAQAAAA==.',
Ri='Rimreaper:BAAANQAECgUICwAAAA==.',
Rn='Rngesus:BAABNQAECoEcAAMOAAkKAhpGLgCUAgAOAAkKIRlGLgCUAgAdAAIK6A3eGwBlAAABNQAECgkJIwADAK0aAA==.',
Ru='Ruffle:BAAANQAECgQIBAAAAA==.Rushem:BAAANQAECgUICAAAAA==.',
Ry='Ryft:BAAANQADCgUIBQAAAA==.',
['Rà']='Ràvenoth:BAAANQAECgYIDwAAAA==.Ràyà:BAAANQADCgQIBAAAAA==.',
Sa='Saenen:BAAANQAECgYIEQAAAA==.',
Sc='Scorchi:BAAANQAECgQJBwAAAA==.',
Se='Serenity:BAAANQADCgYIDAAAAA==.Seseria:BAABNQAECoEYAAIKAAgK4BFuRwAGAgAKAAgK4BFuRwAGAgAAAA==.Sevinofnine:BAAANQAECgIIAwAAAA==.',
Sh='Shadowsong:BAAANQAECgcICgAAAA==.Shaithis:BAAANQADCgQIBgAAAA==.Shamantics:BAAANQADCgcICwABNQADCggIDwABAAAAAA==.Shanic:BAAANQAECgUICAAAAA==.Shavedcat:BAAANQADCgMIAwAAAA==.Shinnylock:BAAANQADCgEIAQAAAA==.Shinokami:BAAANQADCggICAAAAA==.Shocktart:BAAANQAECgIIAgAAAA==.',
Si='Siheal:BAAANQAECgEIAQAAAA==.',
Sn='Snipymagus:BAAANQAECgQIBQABNQAFFAYIEQADAAYdAA==.Snipyterror:BAACNQAFFIERAAMDAAYKBh1OBQDRAQADAAUKOBtOBQDRAQASAAEK5hQPHQBRAAA1AAQKgSYAAwMACQrcI6kHAJoDAAMACQrcI6kHAJoDABIAAQoUBdnmAD0AAAAA.',
So='Socraates:BAAANQABCgQIAgAAAA==.',
Sp='Spacejam:BAAANQADCgYICwAAAA==.Spirallidan:BAABNQAECoEYAAMeAAcKHxIXMgC5AQAeAAcKHxIXMgC5AQAfAAQKngpfRQDHAAAAAA==.',
St='Staticsrexar:BAAANQAECgQIDQAAAA==.Stayk:BAAANQADCgcIDQAAAA==.Stepbro:BAAANQAECgIIAgAAAA==.Stinksauce:BAABNQAECoEZAAQIAAkK0BVfEAB2AgAIAAkK0BVfEAB2AgAbAAMKiQ9EJwCvAAAgAAEKght0GQBOAAAAAA==.Strokntotem:BAAANQADCgYIEQAAAA==.',
Su='Sutra:BAAANQAECgUICwAAAA==.',
Sy='Sylmarillion:BAAANQAECgUIBgAAAA==.',
Ta='Talgulen:BAAANQAECgYIEQAAAA==.Tarquinius:BAAANQAECgUJDwAAAA==.Tasahof:BAAANQABCgEJAQAAAA==.Taynte:BAAANQAECgYIDAAAAA==.',
Th='Thedarkseed:BAAANQADCgYIDAAAAA==.Theoeicke:BAAANQAECgYIDgABNQAECggIGQAPAGsWAA==.',
Ti='Tifferny:BAAANQADCgMIAwAAAA==.',
To='Tone:BAAANQAECggICgAAAA==.Torotatsu:BAAANQAECgIIAQAAAA==.Totemlycool:BAAANQAECgUIBQABNQAECggIIAAPAOATAA==.',
Tr='Traice:BAAANQADCgQIBAAAAA==.Trappress:BAABNQAECoEYAAIFAAcKfxVeXQAKAgAFAAcKfxVeXQAKAgAAAA==.Treehuggër:BAAANQAECgQICQAAAA==.Trelia:BAAANQABCgQIBAAAAA==.Trogkin:BAAANQAECgUIDAABNQAFFAcIDgAEALgVAA==.',
Ty='Tyrith:BAAANQAECgcIEgAAAA==.',
Ug='Ugotgotpal:BAAANQAECgYIDgAAAA==.',
Ul='Ulazain:BAAANQAECgYIEQAAAA==.',
Um='Umadcuzbad:BAAANQADCgcICQAAAA==.',
Us='Usdaprime:BAAANQAECgcIDAAAAA==.',
Va='Vaas:BAAANQAECgYICQAAAA==.Vaporeön:BAAANQAECgcIDAAAAA==.',
Ve='Verric:BAAANQADCgEIAQAAAA==.',
Vi='Viì:BAAANQAECgYIEQAAAA==.',
Vo='Voidarella:BAAANQABCgMIAwABNQAECggIIAALAKUbAA==.',
['Vè']='Vèx:BAABNQAECoEmAAIZAAgKkh7mNwCvAgAZAAgKkh7mNwCvAgAAAA==.',
Wa='Waronyou:BAAANQADCgcIDgABNQAECgcIFQAOANoHAA==.',
Xa='Xavia:BAAANQAECgQIBgAAAA==.',
Yu='Yunaraa:BAAANQAECgIJAwABNQAECgcIGAAFAH8VAA==.',
Yv='Yvana:BAAANQADCgYIEQAAAA==.',
Ze='Zephyrpriest:BAAANQAECgMIBgABNQAFFAcIFgAhAM4jAA==.',
Zo='Zombies:BAAANQAECgUICAAAAA==.',
Zu='Zugmaster:BAABNQAECoEdAAIcAAgKdBdHGgBXAgAcAAgKdBdHGgBXAgAAAA==.',
Zy='Zynn:BAAANQAECgEJAQABNQABCgQIBAABAAAAAA==.',
Zz='Zzephyrdruid:BAACNQAFFIEWAAIhAAcKziO0AADjAgAhAAcKziO0AADjAgA1AAQKgRoAAiEACQrbJdcLAFIDACEACQrbJdcLAFIDAAAA.Zzephyrmage:BAAANQAECgEIAgABNQAFFAcIFgAhAM4jAA==.',
['Çä']='Çärvé:BAAANQADCgIIAgAAAA==.',
['Ôä']='Ôäk:BAAANQADCgUIBQABNQAECgMIBQABAAAAAA==.',
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
