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

local lookup = {'Unknown-Unknown','Mage-Arcane','Mage-Frost','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Feral','Paladin-Protection','DeathKnight-Blood','Evoker-Preservation','Warrior-Protection','Paladin-Holy','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Monk-Windwalker','Priest-Shadow','Priest-Holy','Shaman-Restoration','Druid-Guardian','Druid-Restoration','Hunter-Survival','DeathKnight-Unholy','Warrior-Arms','Warrior-Fury','Priest-Discipline','Evoker-Devastation','Rogue-Assassination','Warlock-Affliction','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Augmentation','Druid-Balance',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abelladanger:BAAANQAECgUIBwAAAA==.',
Ad='Addilyn:BAAANQAECgUICQAAAA==.',
Ag='Agntclappers:BAAANQADCgUJBQAAAA==.Agonyzê:BAAANQADCgQIBAAAAA==.',
Ah='Ahminous:BAAANQAECgUICQAAAA==.Ahroo:BAAANQAECgcIDQABNQAECggIAgABAAAAAQ==.Ahrue:BAAANQAECggIAgAAAQ==.',
Ai='Aikanaro:BAAANQAECgIIAgAAAA==.Airc:BAAANQAECgQIBwAAAA==.',
Aj='Ajanti:BAAANQAECgMIAQAAAA==.',
Al='Alfster:BAAANQAECgMIAwABNQAECgUIDgABAAAAAA==.Allanor:BAAANQADCgEIAQAAAA==.Alliam:BAAANQADCgUIDQAAAA==.',
An='Ancalagon:BAAANQAECgcIEAAAAA==.',
Ar='Argeikeranos:BAABNQAECoEsAAMCAAkKUCAYOAALAwACAAkKzh8YOAALAwADAAIKmx9MIgC4AAAAAA==.',
As='Asystole:BAAANQADCgEIAQAAAA==.',
At='Atheish:BAAANQADCgcICAAAAA==.Atiko:BAAANQADCgQIBAABNQAFFAMIBgAEAA8QAA==.Atomicrednax:BAACNQAFFIEZAAMFAAcKJySDAgBbAgAFAAYKzSSDAgBbAgAGAAEKRSDEJgBjAAA1AAQKgTgAAwUACQqFJdgKABkDAAUACQpEJdgKABkDAAYAAQrwJAgpAU0AAAAA.',
Au='Augtoberfest:BAAANQAECgEIAQABNQAECgIIBAABAAAAAA==.',
Ay='Ayisen:BAAANQADCgYICgAAAA==.',
Ba='Ballsofury:BAABNQAECoEdAAIHAAgK7CaZAQCkAwAHAAgK7CaZAQCkAwAAAA==.Baptism:BAAANQAECgIIAgAAAA==.Battousaiha:BAAANQAECgUICgAAAA==.',
Be='Beezelbubba:BAAANQABCgIIAgAAAA==.',
Bi='Bigmustard:BAAANQADCggICAABNQAFFAcIGAAIACojAA==.',
Bl='Blackcoffee:BAAANQAECgQIBQAAAA==.Blippi:BAAANQADCgQIBgABNQABCgQIBAABAAAAAA==.Bloatlord:BAAANQABCgIIAgAAAA==.',
Bo='Boojum:BAAANQAECgEIAQAAAA==.Bortikus:BAAANQADCgYIBwABNQAECgcIFwAJAEsaAA==.',
Bu='Burney:BAABNQAECoEiAAIKAAgK8B+iCgDqAgAKAAgK8B+iCgDqAgAAAA==.Burnnotice:BAAANQADCgQIBAAAAA==.Busadinn:BAAANQAECgQICwAAAA==.',
['Bò']='Bònesaw:BAABNQAECoElAAILAAgKTiJHBQADAwALAAgKTiJHBQADAwAAAA==.',
Ca='Calibrium:BAAANQAECgYIDQAAAA==.Carll:BAABNQAECoElAAIMAAkKhxoeIQDSAgAMAAkKhxoeIQDSAgAAAA==.',
Ch='Chister:BAAANQAECgcIEgAAAA==.Cholomonga:BAAANQAECgYIBwABNQAFFAcIGAAEAD0bAA==.Churchill:BAAANQADCgUIBQABNQAFFAUIDQANAN0WAA==.',
Co='Colisto:BAAANQADCgQIBAAAAA==.',
Cr='Crazedx:BAAANQAECggICwABNQAFFAUICwAJANUcAA==.Criotor:BAAANQADCgcIBgAAAA==.',
Cy='Cyral:BAAANQAECgQIBgAAAA==.',
Da='Daddy:BAABNQAECoErAAMOAAkKwiEPAgBCAwAOAAkKfh0PAgBCAwAPAAgKphg8SABcAgAAAA==.Daito:BAAANQADCgQIBwAAAA==.Darig:BAAANQAECgIIAgAAAA==.',
De='Deathsrain:BAAANQADCgIIAgAAAA==.Decimas:BAAANQABCgUIBwAAAA==.Decimez:BAAANQAECgUICQAAAA==.Decimock:BAAANQAECgYIEwAAAA==.',
Di='Digerati:BAAANQADCgUIBQAAAA==.Dingiswayo:BAABNQAECoEbAAIQAAgKfxVWIQD0AQAQAAgKfxVWIQD0AQAAAA==.Dingybing:BAAANQAECgUICgAAAA==.Dishwasherx:BAAANQAECgMIBgAAAA==.Dizan:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Dp='Dpitis:BAABNQAECoEmAAMRAAkKPB3jDwDfAgARAAkKPB3jDwDfAgASAAUKWxwJcACVAQAAAA==.',
Dr='Dragonflyy:BAAANQADCgQIBAAAAA==.Draks:BAAANQAECgEJAgAAAA==.Drinkyds:BAABNQAECoEbAAITAAkKLiE7HADhAgATAAkKLiE7HADhAgAAAA==.',
Er='Eriebus:BAAANQAECgUICQAAAA==.Erona:BAAANQAECgUIEAAAAA==.',
Es='Escorpiøn:BAAANQAECgEIAQAAAA==.',
Ev='Evenstar:BAAANQAECgcIBwAAAA==.',
Ex='Extendo:BAAANQAECgYIEAAAAA==.',
Fa='Falkor:BAAANQADCggIDgABNQAECgkJJgARADwdAA==.Fatshock:BAAANQADCggIEAAAAA==.',
Fe='Fearbum:BAAANQAECgcIEgAAAA==.Felagain:BAAANQAECgQIBAAAAA==.Ferdinane:BAAANQAECgUIEAAAAA==.',
Fi='Fidgety:BAAANQADCggIEQAAAA==.',
Fl='Flankshot:BAABNQAECoEjAAIDAAkKlBm+BACwAgADAAkKlBm+BACwAgAAAA==.',
Fo='Foops:BAACNQAFFIEMAAMDAAUKBhisAACNAQADAAUKBhisAACNAQACAAEKpgHDWgA3AAA1AAQKgRsAAgMACQrxHaoFAIoCAAMACQrxHaoFAIoCAAAA.Foopsadin:BAAANQAECgMIBgABNQAFFAUIDAADAAYYAA==.Footloose:BAAANQAECgEIAgAAAA==.',
Fu='Fumìn:BAAANQAECgQIBAAAAA==.',
Ga='Gassommelier:BAAANQADCggICAAAAA==.',
Ge='Geezuss:BAAANQAECgQIBAAAAA==.Genohbreaker:BAAANQAECgUIEAAAAA==.Getrkt:BAAANQAECgUIDQAAAA==.',
Gi='Gimblie:BAABNQAECoEWAAISAAcKoBlJTgAQAgASAAcKoBlJTgAQAgAAAA==.Gimermonty:BAAANQAECgcIEwAAAA==.Gimixx:BAAANQAECgYIDwAAAA==.',
Gl='Gladrielle:BAAANQADCggICgAAAA==.Glatzkaus:BAAANQAECgYICAAAAA==.Glockcena:BAAANQAECgEIAQAAAA==.',
Gn='Gnolom:BAAANQADCgYIBgAAAA==.Gnomedk:BAAANQAECgEIAQAAAA==.',
Gr='Gripen:BAAANQABCggICwAAAA==.Gronk:BAAANQADCgEIAQAAAA==.',
Gu='Guldanshower:BAAANQAECgIIAgAAAA==.Gutterfire:BAAANQABCgQIBAAAAA==.',
Ha='Hakal:BAABNQAECoEjAAIUAAgKpCC/BgDyAgAUAAgKpCC/BgDyAgAAAA==.Halvor:BAAANQAECgIIAgAAAA==.Hangbladz:BAAANQAECgYIEgAAAA==.Hanita:BAAANQAECgMIAwAAAA==.Hardwarë:BAAANQAECgUIEQAAAA==.',
He='Healinghands:BAAANQAECgQICAAAAA==.Hellz:BAABNQAECoElAAILAAgKwBv2CgBjAgALAAgKwBv2CgBjAgAAAA==.',
Hu='Hudochar:BAAANQADCgMIAwAAAA==.Hukdemon:BAAANQAECgUICQAAAA==.',
Ic='Iceandfire:BAAANQAECgIIAwAAAA==.',
Ig='Igneel:BAAANQAECgcIEgABNQAECgkJJgARADwdAA==.',
Iw='Iwillsaverap:BAAANQADCggICAAAAA==.',
Ja='Jaelá:BAAANQADCggICAABNQAECgMIAQABAAAAAA==.',
Je='Jessick:BAAANQAECgIIAgABNQAECggIJQALAE4iAA==.',
Jh='Jhamin:BAACNQAFFIEGAAIEAAMKDxD6FQDnAAAEAAMKDxD6FQDnAAA1AAQKgSQAAwQACQr0GkgvAJoCAAQACQr0GkgvAJoCABMAAwroBkDgAHwAAAAA.',
Jo='Joss:BAAANQAECgMIBAAAAA==.',
Ju='Jubei:BAAANQADCgYIDAAAAA==.Jubeiskyfang:BAAANQAECggICAAAAA==.Julkaal:BAAANQADCgUIBQAAAA==.',
Ka='Kaedrelyn:BAAANQAECgUIBgAAAA==.Kageyuki:BAEANQAECgEIAQABNQAECgkJIgAGACIWAA==.',
Ke='Kennyman:BAAANQADCgQIBAAAAA==.Ketheric:BAAANQADCgMIAwAAAA==.',
Ki='Kindinos:BAAANQADCggIHgAAAA==.',
Kl='Klickyy:BAAANQAECgMIBAABNQAECgkJKgANAP4mAA==.Kllcky:BAABNQAECoEqAAMNAAkK/iaDAQD0AwANAAkK/iaDAQD0AwAMAAEKzAjKAwE5AAAAAA==.',
Kr='Kraun:BAABNQAECoEZAAIGAAcKfSLuLADFAgAGAAcKfSLuLADFAgAAAA==.Kroo:BAABNQAECoEiAAIQAAkKjBPOHQAaAgAQAAkKjBPOHQAaAgAAAA==.',
Ku='Kurnon:BAAANQAECgQIBQABNQAECgUIBgABAAAAAA==.',
Ky='Kyi:BAABNQAECoEfAAIQAAgKyRazHgAQAgAQAAgKyRazHgAQAgAAAA==.',
La='Lammlock:BAAANQAECgYICAAAAA==.Landar:BAABNQAECoEeAAIVAAkKHRaTFwBeAgAVAAkKHRaTFwBeAgAAAA==.Lazurin:BAAANQADCggIEAAAAA==.',
Le='Lebronsamdi:BAAANQADCggICAAAAA==.',
Li='Liara:BAABNQAECoEgAAIWAAkKmxMpBACIAgAWAAkKmxMpBACIAgAAAA==.',
Lo='Lockonyou:BAABNQAECoEVAAIPAAcK2gdTpwBVAQAPAAcK2gdTpwBVAQAAAA==.Losthack:BAAANQAECgUIEAAAAA==.',
Lt='Ltfirebomb:BAAANQADCgIIAQAAAA==.',
Lu='Lutherhuss:BAAANQAECgcIDgAAAA==.',
Ma='Mahra:BAAANQAECgYIEQAAAA==.Manchasone:BAAANQAECggIDwAAAA==.Mangreese:BAAANQAECgcIEQAAAA==.',
Me='Meekseek:BAAANQAECgcICgAAAA==.',
Mi='Miahealifa:BAAANQAECgcIEwAAAA==.Miasma:BAAANQAECgUIDQAAAA==.Micaiah:BAAANQAECgQIBQAAAA==.Mistabubbles:BAAANQAECgcIDwAAAA==.',
Mk='Mk:BAAANQAECgcICgAAAA==.',
Mo='Mochi:BAAANQABCgIIAgAAAA==.Mograinez:BAACNQAFFIEZAAMXAAcKiCYoAADNAgAXAAcKiCYoAADNAgAJAAEKMA6ULgAqAAA1AAQKgRoAAhcACQr1JiYLAE8DABcACQr1JiYLAE8DAAAA.Moosebreath:BAAANQAFFAEIAQAAAA==.',
Ne='Necrussy:BAAANQADCgIIAgAAAA==.Nekrohealia:BAAANQAECgcIBwAAAA==.Neteyam:BAAANQAECgIIAgAAAA==.',
No='Nogitsune:BAAANQADCgEIAQAAAA==.Norolock:BAAANQAECgUICQAAAA==.',
Nu='Nuovis:BAAANQADCgYIBgAAAA==.',
['Nã']='Nãrcissus:BAAANQAECgIIAgABNQAECgkJKgANAP4mAA==.',
Og='Oghlin:BAAANQAECgcIEgAAAA==.',
Oh='Ohwarrior:BAAANQAECgQIBAAAAA==.',
Ol='Oldshotz:BAAANQAECgUIEAAAAA==.',
Om='Omgsteak:BAAANQAECgUIDgAAAA==.',
On='Onlybusa:BAAANQADCgIIAgAAAA==.',
Pa='Palidan:BAAANQAECgcICwAAAA==.Panzerwolf:BAECNQAFFIETAAILAAYKeiUuAACOAgALAAYKeiUuAACOAgA1AAQKgTwABAsACQolJjoBALkDAAsACQolJjoBALkDABgACApxG4ZRAHoCABkABwoNHpsHAFECAAAA.Parsnip:BAAANQAECgQICAAAAA==.',
Pr='Pray:BAAANQAECgMIAwAAAA==.Prayforme:BAABNQAECoEpAAIaAAgKMCMtAQA8AwAaAAgKMCMtAQA8AwAAAA==.Prugaru:BAAANQADCgYIBgAAAA==.',
Ps='Psilocybic:BAABNQAECoEeAAITAAcKpg8jcQCIAQATAAcKpg8jcQCIAQAAAA==.Psychopompos:BAAANQADCggICAABNQAECgkJLAACAFAgAA==.',
Qr='Qreigns:BAAANQAECgEIAQAAAA==.',
Qw='Qweh:BAAANQAECgQIBwAAAA==.',
Ra='Raenia:BAAANQADCgUIBQAAAA==.Rahnko:BAAANQADCgMIAwAAAA==.Rakkasei:BAABNQAECoEaAAIbAAkKpxRrDgBcAgAbAAkKpxRrDgBcAgAAAA==.Rangol:BAAANQADCgYIBgAAAA==.Ravenoth:BAABNQAECoEkAAIcAAcK5h5wHgBiAgAcAAcK5h5wHgBiAgAAAA==.Razkal:BAAANQAECgYIEgAAAA==.Razpal:BAAANQAECgMIAwAAAA==.',
Re='Revirginator:BAAANQAECgQIBQAAAA==.',
Ri='Rimreaper:BAAANQAECgUICwAAAA==.',
Rn='Rngesus:BAABNQAECoEgAAMPAAkKrhqeOACPAgAPAAkKzRmeOACPAgAdAAIK6A1bHwBkAAABNQAFFAMIBgAEAA8QAA==.',
Ru='Ruffle:BAAANQAECgQIBAAAAA==.Rushem:BAAANQAECgUICQAAAA==.',
Ry='Ryft:BAAANQADCgUIBQAAAA==.',
['Rà']='Ràvenoth:BAABNQAECoEVAAIPAAgKUhsCMQCpAgAPAAgKUhsCMQCpAgAAAA==.Ràyà:BAAANQADCgQIBAAAAA==.',
Sa='Saenen:BAABNQAECoEYAAIHAAcKLw2REwCLAQAHAAcKLw2REwCLAQAAAA==.',
Sc='Scorchi:BAAANQAECgQJBwAAAA==.',
Se='Serenity:BAAANQADCgYIDAAAAA==.Seseria:BAABNQAECoEeAAIMAAgKVhTWRwApAgAMAAgKVhTWRwApAgAAAA==.Sevinofnine:BAAANQAECgMIBQAAAA==.',
Sh='Shadowsong:BAAANQAECgcICgAAAA==.Shaithis:BAAANQADCgQIBgAAAA==.Shamantics:BAAANQADCgcICwABNQADCggIDwABAAAAAA==.Shanic:BAAANQAECgUICQAAAA==.Shavedcat:BAAANQADCgMIAwAAAA==.Shinnylock:BAAANQADCgEIAQAAAA==.Shocktart:BAAANQAECgIIAgAAAA==.',
Si='Siheal:BAAANQAECgEIAQAAAA==.',
Sn='Snipymagus:BAAANQAECgQIBQABNQAFFAcIGAAEAD0bAA==.Snipyterror:BAACNQAFFIEYAAMEAAcKPRs6BwDSAQAEAAUKoBs6BwDSAQATAAIKyg2CGACpAAA1AAQKgScAAwQACQrcI3MKAIgDAAQACQrcI3MKAIgDABMAAQoUBU8DATQAAAAA.',
So='Socraates:BAAANQABCgQIAgAAAA==.',
Sp='Spacejam:BAAANQADCgYIEQAAAA==.Specimenb:BAAANQAECggIBAAAAA==.Spirallidan:BAABNQAECoEeAAMeAAgKlBVpKQArAgAeAAgKlBVpKQArAgAfAAQKngqjSwDCAAAAAA==.',
St='Staticsrexar:BAAANQAECgUIEAAAAA==.Stayk:BAAANQADCgcIDQAAAA==.Stepbro:BAAANQAECgIIAgAAAA==.Stinksauce:BAABNQAECoEgAAQKAAkKNxc4EACSAgAKAAkKNxc4EACSAgAgAAUK/hw5CgCjAQAbAAQKsxI4JAD/AAAAAA==.Strokntotem:BAAANQAECgQIBQAAAA==.',
Su='Superchunk:BAAANQAECgIIAgAAAA==.Sutra:BAAANQAECgYIDgAAAA==.',
Sy='Sylmarillion:BAAANQAECgUIBgAAAA==.',
Ta='Talgulen:BAABNQAECoEcAAIbAAgKxBeoDgBWAgAbAAgKxBeoDgBWAgAAAA==.Tarquinius:BAAANQAECgUJDwAAAA==.Taxii:BAAANQAECgQIBAABNQAECgkJIgAYAFsiAA==.Taynte:BAAANQAECgcIDQAAAA==.',
Th='Thedarkseed:BAAANQADCgYIDAAAAA==.Theoeicke:BAABNQAECoEVAAIPAAcKzwmskwCFAQAPAAcKzwmskwCFAQABNQAECggIHwAQAMkWAA==.Thrag:BAAANQABCgUIBQABNQAECgIIAgABAAAAAA==.',
Ti='Tifferny:BAAANQADCgMIAwAAAA==.',
To='Tone:BAAANQAECggICgAAAA==.Torokami:BAAANQAECggIAgAAAA==.Torotatsu:BAAANQAECgIIAQAAAA==.Totemlycool:BAAANQAECgUIBQABNQAECgkJIgAQAIwTAA==.',
Tr='Traice:BAAANQADCgQIBAAAAA==.Trappress:BAABNQAECoEYAAIGAAcKfxWYcwD7AQAGAAcKfxWYcwD7AQABNQAECgkJNAAVAAoeAA==.Treehuggër:BAAANQAECgUIDgAAAA==.Trelia:BAAANQADCgQIBAAAAA==.Trogkin:BAAANQAECgYIEgABNQAFFAcIDwAFALgVAA==.',
Ty='Tyrith:BAAANQAECgcIEwAAAA==.',
Ug='Ugotgotpal:BAAANQAECgYIEwAAAA==.',
Ul='Ulazain:BAABNQAECoEcAAIZAAgK4hl8BgB7AgAZAAgK4hl8BgB7AgAAAA==.',
Um='Umadcuzbad:BAAANQADCgcICQAAAA==.',
Us='Usdaprime:BAAANQAECgcIEAAAAA==.',
Va='Vaas:BAAANQAECgYICwAAAA==.Vaporeön:BAAANQAECgcIDQAAAA==.Varrasha:BAAANQABCgIIAgAAAA==.',
Ve='Verric:BAAANQADCgEIAQAAAA==.',
Vi='Viì:BAABNQAECoEYAAINAAcKlQy3rACNAQANAAcKlQy3rACNAQAAAA==.',
Vo='Voidarella:BAAANQABCgMIAwABNQAECggIIgANAAEcAA==.',
['Vè']='Vèx:BAABNQAECoEqAAIYAAkK5h4bKQAFAwAYAAkK5h4bKQAFAwAAAA==.',
Wa='Waronyou:BAAANQADCgcIDgABNQAECgcIFQAPANoHAA==.Watlas:BAAANQAECgMIAwABNQAECgkJJgAXALYlAA==.',
Xa='Xavia:BAAANQAECgUICwAAAA==.',
Yu='Yunaraa:BAAANQAECgIJAwABNQAECgkJNAAVAAoeAA==.',
Yv='Yvana:BAAANQADCgYIEQAAAA==.',
Ze='Zephyrpriest:BAAANQAECgMIBgABNQAFFAcIFwAhAM4jAA==.',
Zo='Zombies:BAAANQAECgUICQAAAA==.',
Zu='Zugmaster:BAABNQAECoEkAAIcAAgKkxdpIgBFAgAcAAgKkxdpIgBFAgAAAA==.',
Zy='Zynn:BAAANQAECgEJAQABNQABCgQIBAABAAAAAA==.',
Zz='Zzephyrdruid:BAACNQAFFIEXAAIhAAcKziNFAQDOAgAhAAcKziNFAQDOAgA1AAQKgRoAAiEACQrbJZsPADoDACEACQrbJZsPADoDAAAA.Zzephyrmage:BAAANQAECgMIBAABNQAFFAcIFwAhAM4jAA==.',
['Çä']='Çärvé:BAAANQADCgIIAgAAAA==.',
['Ôä']='Ôäk:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.',
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
