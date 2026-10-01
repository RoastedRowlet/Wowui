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

local lookup = {'Shaman-Enhancement','Unknown-Unknown','Priest-Discipline','Priest-Holy','Druid-Feral','Paladin-Retribution','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Warrior-Arms','DemonHunter-Devourer','Mage-Frost','Mage-Fire','DeathKnight-Unholy','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Warlock-Affliction','Monk-Windwalker',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Accultademic:BAAANQABCggIEgAAAA==.',
Ae='Aeliena:BAAANQADCgYIFwAAAA==.',
Ai='Airess:BAAANQABCgEIAQAAAA==.Airstang:BAAANQADCgQIBAAAAA==.',
Al='Allan:BAAANQAECgcIDwAAAA==.',
Am='Amal:BAABNQAECoEqAAIBAAkKlBtOBwDiAgABAAkKlBtOBwDiAgAAAA==.Amaneeda:BAAANQAECgIIBAABNQAECgQIBQACAAAAAA==.Amazonia:BAAANQAECgEIAQAAAA==.',
An='Antagonis:BAAANQADCggIHgAAAA==.',
Ap='Apeximmortal:BAAANQADCggICAAAAA==.Apexlight:BAAANQADCgQIBAAAAA==.',
Ar='Aranthal:BAAANQAECgcIBwAAAA==.Arashe:BAAANQADCggIIwAAAA==.Arganos:BAAANQAECgYIEgAAAA==.Arkburn:BAAANQADCgcIEQAAAA==.Arkfur:BAAANQABCgQIBAAAAA==.',
As='Ashiond:BAAANQAECgEIAQAAAA==.Astrocat:BAAANQADCggIDgAAAA==.',
At='Atheîst:BAABNQAECoEjAAMDAAkKbSKVAQAMAwAEAAgKXiFLEgAMAwADAAgKXyGVAQAMAwAAAA==.Atsuni:BAAANQAECgYIEwAAAA==.',
Au='Aurite:BAAANQAFFAMIAwAAAQ==.',
Av='Aventon:BAAANQADCgQIBAABNQAECgYIEgACAAAAAA==.',
Az='Azrand:BAAANQADCggIJQAAAA==.',
Ba='Baelanoth:BAAANQAECgUIBwAAAA==.Balkazaar:BAAANQAFFAIIAwAAAA==.Bammbamm:BAAANQAECgMICAAAAA==.Banewreak:BAAANQAECgYIEQAAAA==.Banu:BAAANQADCgYIDgAAAA==.Baradin:BAAANQADCgcICAAAAA==.',
Be='Bearybutt:BAAANQAECgEIAQABNQAECggIIgAFAPUcAA==.Belanklin:BAAANQADCggIHwAAAA==.',
Bi='Bigak:BAAANQADCgUIBQAAAA==.Bigdisc:BAAANQAECgMIBwABNQAECgYIDQACAAAAAA==.Biqdonk:BAAANQADCgQIBAAAAA==.',
Bl='Bloodlily:BAAANQADCgMIAwAAAA==.Bloodravage:BAAANQADCgUIBQAAAA==.',
Bo='Boogie:BAABNQAECoEeAAIGAAgKqBY8WAA6AgAGAAgKqBY8WAA6AgAAAA==.Bossa:BAAANQADCgIJAgAAAA==.Bossbeast:BAAANQABCgIIAgABNQAECgIIAgACAAAAAA==.Bossdwarf:BAAANQAECgIIAgAAAA==.Bosslock:BAAANQADCgYIBgAAAA==.',
Br='Breakstuff:BAAANQAECgIIAgAAAA==.',
Bu='Bubbleosévèn:BAAANQAECgEIAQABNQAECgkJIwADAG0iAA==.Buckshot:BAAANQABCgIIAgAAAA==.',
['Bú']='Búbblés:BAAANQAECggIDgAAAA==.',
Ca='Caatia:BAABNQAECoEiAAIGAAkKGh9QIQAOAwAGAAkKGh9QIQAOAwAAAA==.Capzeil:BAAANQAECgQIBQAAAA==.Carthel:BAAANQAECgYIEAAAAA==.',
Ce='Cerrydwyn:BAAANQAECgIJAgAAAA==.',
Ch='Charley:BAAANQADCgYJBwAAAA==.Chasseresse:BAAANQAECgEIAQAAAA==.Cherry:BAABNQAECoEhAAIHAAkK6RhPYwCJAgAHAAkK6RhPYwCJAgAAAA==.Chiryoshi:BAAANQADCggICwAAAA==.',
Cl='Clearly:BAAANQAECgEIAQAAAA==.',
Cm='Cmondie:BAAANQAECgEIAQAAAA==.',
Cr='Crackmonkéy:BAABNQAECoEhAAIEAAgKhhs8KACNAgAEAAgKhhs8KACNAgAAAA==.Cronoz:BAAANQAECgUICQAAAA==.',
Cu='Cursess:BAACNQAFFIEJAAMIAAUK+g5EDgArAQAIAAQKMxBEDgArAQAJAAEKFQrqFQBUAAA1AAQKgRsAAwgACQo3H7BFAD8CAAgABwoSHrBFAD8CAAkABApmGc0oAB0BAAAA.',
['Cà']='Càrnagè:BAAANQADCgYIDAAAAA==.',
['Có']='Cózmik:BAAANQAECgIIAgAAAA==.',
Da='Dace:BAAANQABCgYIBwAAAA==.Dalfion:BAAANQADCggICQAAAA==.Daliela:BAAANQAECgYIDQAAAA==.Dalya:BAAANQAECgUICwAAAA==.Damsham:BAAANQABCgYICwAAAA==.Dani:BAAANQABCgEIAQABNQAECgEIAQACAAAAAA==.Dayel:BAAANQADCgUIBwABNQADCggICwACAAAAAA==.',
De='Deathratell:BAAANQABCgIIAgAAAA==.Deemaius:BAAANQADCgEIAQAAAA==.Dekunarreia:BAAANQADCgYIBgAAAA==.Demonatrixx:BAAANQADCgMIBAAAAA==.Destinÿ:BAAANQAECgYIDQAAAA==.Devourer:BAAANQAECgMICAAAAA==.',
Dg='Dguidon:BAAANQADCgEIAQAAAA==.',
Di='Dist:BAAANQAECgYIBgAAAA==.',
Dr='Drakentales:BAAANQADCgQIBAAAAA==.Drathunia:BAAANQADCgYJDgAAAA==.Dreathhammer:BAABNQAECoEgAAIKAAgKvyPkDgAyAwAKAAgKvyPkDgAyAwAAAA==.Dräwn:BAAANQADCgYIBgAAAA==.Drízzt:BAAANQABCgQIBgAAAA==.',
Du='Dundyrn:BAAANQAECgYICwAAAA==.Dunhallow:BAAANQAECgQIBQABNQAECgYICwACAAAAAA==.',
El='Elememetal:BAAANQAECgMJAwAAAA==.Elvenia:BAAANQADCgMIAwAAAA==.',
Ev='Evers:BAAANQADCgYIBgAAAA==.',
Fa='Fashaw:BAAANQAECgEIAQAAAA==.Fatherjug:BAAANQADCgMIAwAAAA==.Fatpao:BAAANQAECgIIBQAAAA==.Faunt:BAAANQAECgIIAgAAAA==.',
Fe='Felmorn:BAAANQADCgYIBgABNQAECgYIEgACAAAAAA==.Femboy:BAAANQAECgYJBgAAAA==.',
Fo='Foldyholds:BAABNQAECoEiAAIHAAgKzSLsMwAGAwAHAAgKzSLsMwAGAwAAAA==.Foulbert:BAAANQAECgYICAAAAA==.',
Fu='Furyofdawn:BAAANQAECgQIBwAAAA==.',
['Fá']='Fálola:BAAANQADCgMIAwAAAA==.Fálísta:BAAANQAECgMIAwABNQADCgMIAwACAAAAAA==.',
Ga='Gamblex:BAAANQADCggIJgAAAA==.Garviel:BAAANQAECgMIBQAAAA==.',
Ge='Geethatlock:BAAANQADCgMJAwAAAA==.',
Gh='Ghlaircan:BAAANQADCgQIBAAAAA==.',
Gi='Gimleia:BAAANQAECgEIAQAAAA==.',
Gl='Glanth:BAAANQAECggIDwAAAA==.',
Gn='Gnips:BAAANQABCgYICQAAAA==.',
Go='Gooddeeds:BAAANQADCgQIBAAAAA==.Goontar:BAAANQAECgYICwAAAA==.',
Gr='Graider:BAAANQADCgIIAgABNQAECgkJIwADAG0iAA==.Greensoul:BAAANQAECgUIDgAAAA==.',
Gu='Gundyr:BAAANQADCggIDgAAAA==.',
Ha='Hahaha:BAAANQADCgcIBwABNQAECgkJIQALANIcAA==.Halammela:BAAANQADCgYICAABNQAECgYJEwACAAAAAA==.Halfas:BAAANQADCgQIBQAAAA==.Harmen:BAAANQADCggICAAAAA==.',
He='Heavenlyfïre:BAAANQAECgUIBQAAAA==.Helleer:BAAANQADCgQIBwAAAA==.',
Hi='Hikdh:BAAANQAECgYIEAAAAA==.Hikwar:BAAANQAECgQIBQABNQAECgYIEAACAAAAAA==.',
Ho='Hobohunter:BAAANQAECggIBwAAAA==.Hobopally:BAAANQAECggICAAAAA==.Hogun:BAAANQABCgIIAgAAAA==.',
['Hä']='Hämmer:BAAANQADCgEIAQAAAA==.',
Ia='Iamreggi:BAAANQADCgUIBQAAAA==.',
Ih='Ihealzufool:BAAANQADCgQIBAABNQAECgUIBwACAAAAAA==.',
Im='Im:BAAANQADCgcIBwAAAA==.Importor:BAAANQADCgUIBQAAAA==.',
Ja='Jalene:BAAANQADCgMIAwAAAA==.',
Jd='Jdai:BAAANQADCgUICQAAAA==.',
Jo='Jocecilla:BAAANQAECgQIBgABNQAECgkJIgAGABofAA==.',
Ju='Juglight:BAAANQAECgIJAwAAAA==.Junovay:BAAANQADCgUJBQABNQAECgEIAQACAAAAAA==.',
Ka='Karannya:BAAANQADCgQIBAAAAA==.Karrah:BAAANQADCggIHgAAAA==.Kaz:BAABNQAECoEfAAMGAAgKPRXxZAATAgAGAAgKPRXxZAATAgAKAAMKEgTLzQCHAAAAAA==.',
Ke='Keebbler:BAAANQABCgIIAgAAAA==.Kekdemon:BAAANQAECgUIBQABNQAECggIIgAFAPUcAA==.',
Kh='Khaiv:BAABNQAECoE1AAIMAAkK2CTdAgCgAwAMAAkK2CTdAgCgAwAAAA==.',
Ki='Kielann:BAAANQAECgMICAAAAA==.Kimmi:BAAANQADCgcIGAAAAA==.',
Ko='Korihor:BAAANQAECgMICAAAAA==.',
Ky='Kyuuof:BAAANQADCgIIAgAAAA==.',
La='Larinne:BAAANQADCgMJBQAAAA==.Larolod:BAAANQADCgcICwAAAA==.Lasadin:BAAANQABCgYIDAAAAA==.',
Le='Lechwe:BAAANQAECgYIDQAAAA==.Legolase:BAAANQAECgEIAQAAAA==.Lenry:BAACNQAFFIEIAAMNAAQK5h15AgDFAAAHAAMKjxuRIAADAQANAAIKcCF5AgDFAAA1AAQKgSUAAwcACQoXI98nACsDAAcACQoXI98nACsDAA4AAwrTDt4FAMIAAAAA.',
Li='Lichmajor:BAABNQAECoEgAAIPAAgKxBTTNAD3AQAPAAgKxBTTNAD3AQAAAA==.Lightfeet:BAAANQADCggIGQABNQAECggILgAQACQYAA==.Lionladi:BAAANQADCgQIBAAAAA==.',
Lo='Loenn:BAAANQADCgQIBAAAAA==.Lostdelta:BAAANQADCgIIAgABNQAECgcIGQALAEIYAA==.Lostrage:BAABNQAECoEZAAILAAcKQhi1cgDuAQALAAcKQhi1cgDuAQAAAA==.Lovepet:BAABNQAECoEuAAMQAAgKJBg1RwBMAgAQAAgKJBg1RwBMAgARAAcK4wjeMgBZAQAAAA==.',
Lt='Ltlesunshine:BAAANQADCgUIBQAAAA==.',
Lu='Lubù:BAAANQAECgYIDAABNQAECggIIQAEAIYbAA==.Lunal:BAABNQAECoEjAAIHAAkKTRUBXQCZAgAHAAkKTRUBXQCZAgAAAA==.',
Ly='Lyda:BAAANQAECgMICAAAAA==.',
['Lû']='Lûnitari:BAAANQADCggIFwAAAA==.',
Ma='Magice:BAAANQADCggIJgAAAA==.Malibubarbie:BAAANQAECgMICAAAAA==.Malystron:BAAANQADCggIEAAAAA==.Marollus:BAAANQABCgYIDgAAAA==.Materesa:BAAANQAECgYIEAAAAA==.Maysty:BAAANQAECgUIDwAAAA==.',
Me='Meiyuki:BAAANQADCgQIBAAAAA==.Menapaws:BAACNQAFFIEHAAISAAMKpB3nDgAHAQASAAMKpB3nDgAHAQA1AAQKgSUAAhIACQrKJGIFAJwDABIACQrKJGIFAJwDAAAA.Meriel:BAAANQADCgYJBgAAAA==.',
Mi='Midouri:BAAANQADCgMIAwAAAA==.Milk:BAAANQADCgUIBQAAAA==.',
Mo='Moonbayne:BAABNQAECoEVAAISAAYK/x74LgAiAgASAAYK/x74LgAiAgAAAA==.Mooszer:BAAANQADCgYIBgAAAA==.Moritz:BAAANQAECgUIDAAAAA==.Motomoto:BAABNQAECoEWAAIGAAkKthL5XgAlAgAGAAkKthL5XgAlAgAAAA==.',
Ms='Ms:BAABNQAECoEhAAILAAkK0hyFMQDIAgALAAkK0hyFMQDIAgAAAA==.',
Mu='Muffinmon:BAAANQAECgEIAQAAAA==.Mushinx:BAAANQADCgUICAAAAA==.',
Na='Nasta:BAAANQAECgcIDAAAAA==.Naxxgoblin:BAAANQAECgIIAgAAAA==.',
Ne='Nepharim:BAAANQAECgQICQAAAA==.Nephlim:BAABNQAECoEgAAMTAAkKSiNsCwANAwATAAkKgiFsCwANAwAPAAgKSiIacwDcAAAAAA==.',
Oa='Oakenmuffin:BAAANQABCgIIAgAAAA==.Oatie:BAAANQAECgUICAAAAA==.',
Ob='Oberoñ:BAAANQADCgMIAwAAAA==.',
Om='Om:BAAANQAECgIIAwAAAA==.',
Oo='Oorlian:BAAANQADCggIJgAAAA==.',
Op='Opheleia:BAAANQAECgIIAgAAAA==.',
Pa='Pantoprazole:BAAANQADCgYIAwAAAA==.Pastor:BAAANQADCgYIBwABNQADCgUIBQACAAAAAA==.Patramia:BAAANQABCgYJBgAAAA==.Pawtyanimal:BAAANQAECgMICAAAAA==.',
Po='Pocketbible:BAAANQAECgUIBwAAAA==.Pogo:BAAANQAECgQJBwAAAA==.Pongmo:BAAANQAECgcIEwAAAA==.',
Pu='Punchaurbuns:BAAANQABCgQJBAAAAA==.',
Py='Pyylot:BAAANQAECgEIAQAAAA==.',
Ra='Ramuel:BAAANQAECgQICAAAAA==.Rastapopulos:BAAANQAECgMIBAAAAA==.Razhul:BAAANQABCgIIAgAAAA==.',
Re='Reaver:BAAANQAECgQICwAAAA==.Reg:BAAANQAECgcIDAAAAA==.',
Ri='Rikaku:BAAANQADCggIJgAAAA==.',
Ro='Rosemery:BAAANQAECgMIBAAAAA==.',
Ru='Ru:BAAANQAECgQIBgAAAA==.',
['Râ']='Râpodac:BAAANQAECgUIEQAAAA==.',
Sa='Sangwin:BAAANQADCgEIAQAAAQ==.Sapheluna:BAAANQABCgEIAQAAAA==.',
Sc='Schizo:BAAANQAECgEIAQABNQAECgkJIQALANIcAA==.',
Se='Selistira:BAAANQABCgMIAQAAAA==.Semdorii:BAAANQAECgYIEAAAAA==.Sephywrath:BAAANQAECgUJCwAAAA==.Serabignite:BAAANQADCgIIAgABNQAECggIJwAUAJchAA==.Seralith:BAABNQAECoEcAAMPAAgKzCE1IACAAgAPAAYKGyQ1IACAAgATAAcK/x2sIAA2AgAAAA==.Seranight:BAABNQAECoEnAAMUAAgKlyHAFADaAgAUAAgKlyHAFADaAgATAAYKEgW5UADpAAAAAA==.Seven:BAAANQAECgUICwABNQADCgIIAgACAAAAAA==.Sevenpaws:BAAANQAECgQICAABNQAECgkJIwADAG0iAA==.',
Sh='Shadowchi:BAAANQAECgEIAQAAAA==.Shaolinmonk:BAAANQAECgMIBgAAAA==.Shirohige:BAAANQADCggIJgAAAA==.Shämwìch:BAAANQADCgEIAQAAAA==.Shådôw:BAAANQADCgUIBgABNQAECgkJIgAGABofAA==.',
Si='Sicarius:BAAANQADCgEJAQAAAA==.Silvanoshi:BAAANQADCgcICQABNQADCggICwACAAAAAA==.',
Sk='Skaïlar:BAAANQADCgEIAQAAAA==.',
Sn='Snayre:BAAANQADCgIJAgAAAA==.Snipêr:BAAANQADCggIDgAAAA==.',
So='Soonita:BAAANQADCgUIBQAAAA==.Soularis:BAAANQADCgYIDAAAAA==.',
Sp='Spybro:BAAANQADCggIFwAAAA==.',
St='Stalkingwolf:BAAANQADCggIHgAAAA==.Stéàlth:BAAANQADCggIDQABNQAECgkJIgAGABofAA==.',
Su='Sunrisewood:BAAANQADCgMIBgAAAA==.Suzuya:BAAANQAECgMIAwAAAA==.',
Sy='Sylailia:BAABNQAECoEaAAISAAgKXBNNMAAYAgASAAgKXBNNMAAYAgAAAA==.Synistir:BAAANQADCgUIEQAAAA==.Syrø:BAAANQAECgQJBQAAAA==.',
Ta='Tanyon:BAAANQADCgYIBgAAAA==.Tarlynna:BAAANQAECgMIAwAAAA==.',
Tc='Tcalin:BAAANQAECgUICAAAAA==.Tcon:BAAANQADCgQIBAAAAA==.',
Td='Tdragon:BAAANQADCgIIAgABNQAECgUIBwACAAAAAA==.',
Th='Thammer:BAAANQAECgUIBwAAAA==.Throndor:BAAANQADCggICQAAAA==.Thundarah:BAAANQADCgYIDgAAAA==.',
Ti='Tiarcis:BAAANQAECgYIEQAAAA==.',
To='Toughgirlone:BAAANQADCgIIAgAAAA==.',
Tr='Treesummoner:BAABNQAECoEsAAQJAAgK2CH/BAC+AgAJAAcKKCL/BAC+AgAIAAEKqR/G9gBbAAAVAAEKuQIALAAgAAAAAA==.Triton:BAABNQAECoEZAAIGAAgKMh+VNQC0AgAGAAgKMh+VNQC0AgAAAA==.Trizuke:BAAANQADCgQIBQAAAA==.',
Tu='Tutsee:BAAANQADCgUJBQAAAA==.',
Va='Valeyka:BAAANQAECgQIBAAAAA==.Vali:BAAANQADCggIDwAAAA==.Valle:BAAANQAECgIJAgAAAA==.Vasilia:BAAANQAECgMICAAAAA==.',
Ve='Velanna:BAAANQAECgQIBAAAAA==.Veliatt:BAAANQAECgYICwAAAA==.Vexaris:BAABNQAECoEwAAINAAkKOhzFAgD6AgANAAkKOhzFAgD6AgAAAA==.',
Vi='Viradi:BAAANQADCgcIEAAAAA==.',
Wa='Wagonburner:BAAANQAECgEJAQAAAA==.',
Wu='Wulfbayne:BAAANQADCgMIAwAAAA==.',
Xa='Xalatoes:BAAANQAECgEIAQAAAA==.',
Xi='Xianfei:BAABNQAECoEeAAIWAAkKgBhdEQCUAgAWAAkKgBhdEQCUAgAAAA==.',
Za='Zachxd:BAAANQAECgYIDgABNQAECgkJIQALANIcAA==.Zanthe:BAAANQADCggIHQAAAA==.Zappletree:BAAANQADCgQIBAAAAA==.Zarilice:BAAANQADCgEIAgABNQAECggIHAAPAMwhAA==.',
Zh='Zhanblood:BAAANQAECgQIBgABNQAECgQJCQACAAAAAA==.Zhanbrew:BAAANQAECgQJCQAAAA==.',
Zi='Zipit:BAABNQAECoEgAAIJAAgKxxRXCQBUAgAJAAgKxxRXCQBUAgAAAA==.',
Zs='Zsynn:BAAANQADCgcIBwAAAA==.',
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
