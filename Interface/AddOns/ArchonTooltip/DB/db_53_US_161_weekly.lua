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

local lookup = {'Shaman-Enhancement','Priest-Discipline','Priest-Holy','Unknown-Unknown','Druid-Feral','Paladin-Retribution','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Warrior-Arms','DemonHunter-Devourer','Mage-Fire','DeathKnight-Unholy','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Warlock-Affliction','Mage-Frost',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=53,date='2026-09-22',data={Ae='Aeliena:BAAANQADCgUIEAAAAA==.',
Ai='Airess:BAAANQABCgEIAQAAAA==.Airstang:BAAANQADCgQIBAAAAA==.',
Al='Allan:BAAANQAECgYJCAAAAA==.',
Am='Amal:BAABNQAECoEoAAIBAAkKlBs/BQACAwABAAkKlBs/BQACAwAAAA==.Amaneeda:BAAANQAECgIJAgAAAA==.Amazonia:BAAANQAECgEIAQAAAA==.',
An='Antagonis:BAAANQADCgcJFgAAAA==.',
Ap='Apeximmortal:BAAANQADCggICAAAAA==.',
Ar='Aranthal:BAAANQADCgcICAAAAA==.Arashe:BAAANQADCggIGwAAAA==.Arganos:BAAANQAECgYJDAAAAA==.Arkburn:BAAANQADCgYICgAAAA==.Arkfur:BAAANQABCgQIBAAAAA==.',
As='Ashiond:BAAANQAECgEIAQAAAA==.Astrocat:BAAANQADCggIDgAAAA==.',
At='Atheîst:BAABNQAECoEaAAMCAAgKBSEcAgDDAgACAAcKbSIcAgDDAgADAAMKXB3ecQAPAQAAAA==.Atsuni:BAAANQAECgYIDQAAAA==.',
Au='Aurite:BAAANQAFFAIIAgAAAQ==.',
Av='Aventon:BAAANQADCgQIBAABNQAECgYJDAAEAAAAAA==.',
Az='Azrand:BAAANQADCgcJHQAAAA==.',
Ba='Baelanoth:BAAANQAECgIJAgAAAA==.Balkazaar:BAAANQAFFAIIAgAAAA==.Bammbamm:BAAANQAECgMJBgAAAA==.Banewreak:BAAANQAECgYJDQAAAA==.Banu:BAAANQADCgYIDAAAAA==.Baradin:BAAANQADCgcICAAAAA==.',
Be='Bearybutt:BAAANQABCgMIAwABNQAECggJGgAFANIbAA==.Belanklin:BAAANQADCggIHwAAAA==.',
Bi='Bigak:BAAANQADCgUIBQAAAA==.Bigdisc:BAAANQAECgMJBwABNQAECgQJBwAEAAAAAA==.Biqdonk:BAAANQADCgQIBAAAAA==.',
Bl='Bloodlily:BAAANQADCgMIAwAAAA==.Bloodravage:BAAANQADCgUIBQAAAA==.',
Bo='Boogie:BAAANQAECgcJEgAAAA==.Bossa:BAAANQADCgIJAgAAAA==.Bossdwarf:BAAANQAECgIIAgAAAA==.Bosslock:BAAANQADCgYIBgAAAA==.',
Br='Breakstuff:BAAANQAECgIIAgAAAA==.',
Bu='Buckshot:BAAANQABCgIIAgAAAA==.',
['Bú']='Búbblés:BAAANQAECggICgAAAA==.',
Ca='Caatia:BAABNQAECoEWAAIGAAkKRR3RHQD4AgAGAAkKRR3RHQD4AgAAAA==.Capzeil:BAAANQAECgIIAwAAAA==.Carthel:BAAANQAECgYJEAAAAA==.',
Ce='Cerrydwyn:BAAANQAECgIJAgAAAA==.',
Ch='Charley:BAAANQADCgYJBwAAAA==.Chasseresse:BAAANQAECgEIAQAAAA==.Cherry:BAABNQAECoEaAAIHAAgKphmNagBSAgAHAAgKphmNagBSAgAAAA==.Chiryoshi:BAAANQADCgcJCgAAAA==.',
Cl='Clearly:BAAANQAECgEIAQAAAA==.',
Cr='Crackmonkéy:BAABNQAECoEZAAIDAAgKjxkpJwBmAgADAAgKjxkpJwBmAgAAAA==.Cronoz:BAAANQAECgQIBgAAAA==.',
Cu='Cursess:BAABNQAECoEYAAMIAAkKHR/zNQBGAgAIAAcK8B3zNQBGAgAJAAQKZhmHJAApAQAAAA==.',
['Cà']='Càrnagè:BAAANQADCgYIDAAAAA==.',
['Có']='Cózmik:BAAANQADCgIIAgAAAA==.',
Da='Dace:BAAANQABCgYIBwAAAA==.Daliela:BAAANQAECgQJBwAAAA==.Dalya:BAAANQAECgQIBwAAAA==.Damsham:BAAANQABCgYICwAAAA==.Dani:BAAANQABCgEIAQABNQADCgYJBgAEAAAAAA==.Dayel:BAAANQADCgIIAgABNQADCgcJCgAEAAAAAA==.',
De='Deathratell:BAAANQABCgIIAgAAAA==.Deemaius:BAAANQADCgEIAQAAAA==.Demonatrixx:BAAANQADCgMIBAAAAA==.Destinÿ:BAAANQAECgQJBwAAAA==.Devourer:BAAANQAECgMJBgAAAA==.',
Dg='Dguidon:BAAANQADCgEIAQAAAA==.',
Di='Dist:BAAANQAECgYIBgAAAA==.',
Dr='Drakentales:BAAANQADCgQIBAAAAA==.Drathunia:BAAANQADCgYJDgAAAA==.Dreathhammer:BAABNQAECoEYAAIKAAgKiiGrDwAOAwAKAAgKiiGrDwAOAwAAAA==.Dräwn:BAAANQADCgYIBgAAAA==.Drízzt:BAAANQABCgQIBgAAAA==.',
Du='Dundyrn:BAAANQAECgUJBQAAAA==.Dunhallow:BAAANQAECgQIBQABNQAECgUJBQAEAAAAAA==.',
El='Elememetal:BAAANQAECgMJAwAAAA==.Elvenia:BAAANQADCgMIAwAAAA==.',
Fa='Fashaw:BAAANQAECgEIAQAAAA==.Fatherjug:BAAANQADCgMIAwAAAA==.Fatpao:BAAANQAECgEJAwAAAA==.',
Fe='Felmorn:BAAANQADCgYIBgABNQAECgYJDAAEAAAAAA==.Femboy:BAAANQAECgYJBgAAAA==.',
Fo='Foldyholds:BAABNQAECoEbAAIHAAgKux/JNQDsAgAHAAgKux/JNQDsAgAAAA==.Foulbert:BAAANQAECgUIBwAAAA==.',
Fu='Furyofdawn:BAAANQAECgQJBAAAAA==.',
['Fá']='Fálola:BAAANQADCgMJAwAAAA==.Fálísta:BAAANQAECgEJAQABNQADCgMJAwAEAAAAAA==.',
Ga='Gamblex:BAAANQADCggIHgAAAA==.Garviel:BAAANQAECgIJAgAAAA==.',
Ge='Geethatlock:BAAANQADCgMJAwAAAA==.',
Gh='Ghlaircan:BAAANQADCgQIBAAAAA==.',
Gi='Gimleia:BAAANQAECgEIAQAAAA==.',
Gl='Glanth:BAAANQAECggIDwAAAA==.',
Gn='Gnips:BAAANQABCgYICQAAAA==.',
Go='Gooddeeds:BAAANQADCgQIBAAAAA==.Goontar:BAAANQAECgYJCAAAAA==.',
Gr='Greensoul:BAAANQAECgUJCQAAAA==.',
Gu='Gundyr:BAAANQADCggIDgAAAA==.',
Ha='Hahaha:BAAANQADCgcIBwABNQAECgkJGwALANMWAA==.Halammela:BAAANQADCgYJCAABNQAECgYJEwAEAAAAAA==.Halfas:BAAANQADCgQJBAAAAA==.Harmen:BAAANQADCggICAAAAA==.',
He='Heavenlyfïre:BAAANQAECgUIBQAAAA==.Helleer:BAAANQADCgIJAwAAAA==.',
Hi='Hikdh:BAAANQAECgYJCgAAAA==.Hikwar:BAAANQAECgMJAwABNQAECgYJCgAEAAAAAA==.',
Ho='Hobohunter:BAAANQAECggIBwAAAA==.Hogun:BAAANQABCgIIAgAAAA==.',
['Hä']='Hämmer:BAAANQADCgEIAQAAAA==.',
Ia='Iamreggi:BAAANQADCgUIBQAAAA==.',
Ih='Ihealzufool:BAAANQADCgQIBAABNQAECgIJAgAEAAAAAA==.',
Im='Im:BAAANQADCgcIBwAAAA==.',
Ja='Jalene:BAAANQADCgMIAwAAAA==.',
Jd='Jdai:BAAANQADCgUICQAAAA==.',
Jo='Jocecilla:BAAANQAECgIJAgABNQAECgkJFgAGAEUdAA==.',
Ju='Juglight:BAAANQAECgIJAwAAAA==.Junovay:BAAANQADCgUJBQABNQADCggIDQAEAAAAAA==.',
Ka='Karannya:BAAANQADCgQIBAAAAA==.Karrah:BAAANQADCgcJFgAAAA==.Kaz:BAABNQAECoEYAAMGAAgKLRSkaQDAAQAGAAcKwRSkaQDAAQAKAAMKEgQnsgCOAAAAAA==.',
Ke='Keebbler:BAAANQABCgIIAgAAAA==.Kekdemon:BAAANQADCgcIBwABNQAECggJGgAFANIbAA==.',
Kh='Khaiv:BAABNQAECoEjAAIMAAkK2iNfDwDBAgAMAAkK2iNfDwDBAgAAAA==.',
Ki='Kielann:BAAANQAECgMJBgAAAA==.Kimmi:BAAANQADCgUIEAAAAA==.',
Ko='Korihor:BAAANQAECgMJBgAAAA==.',
La='Larinne:BAAANQADCgMJBQAAAA==.Larolod:BAAANQADCgcIBwAAAA==.Lasadin:BAAANQABCgYIDAAAAA==.',
Le='Lechwe:BAAANQAECgUJDAAAAA==.Lenry:BAABNQAECoEjAAMHAAkK8yJcHABFAwAHAAkK8yJcHABFAwANAAMK0w7mBADKAAAAAA==.',
Li='Lichmajor:BAABNQAECoEYAAIOAAgKhhFOKwAQAgAOAAgKhhFOKwAQAgAAAA==.Lightfeet:BAAANQADCggIGQABNQAECggIIwAPAJMWAA==.',
Lo='Loenn:BAAANQADCgQIBAAAAA==.Lostdelta:BAAANQADCgIIAgABNQAECgYJDwAEAAAAAA==.Lostrage:BAAANQAECgYJDwAAAA==.Lovepet:BAABNQAECoEjAAMPAAgKkxbxOQBNAgAPAAgKkxbxOQBNAgAQAAYKmgZQMwAUAQAAAA==.',
Lt='Ltlesunshine:BAAANQADCgUIBQAAAA==.',
Lu='Lubù:BAAANQAECgUJBgABNQAECggIGQADAI8ZAA==.Lunal:BAABNQAECoEbAAIHAAgKcxI9fAAhAgAHAAgKcxI9fAAhAgAAAA==.',
Ly='Lyda:BAAANQAECgMJBgAAAA==.',
['Lû']='Lûnitari:BAAANQADCgcJFgAAAA==.',
Ma='Magice:BAAANQADCggIHgAAAA==.Malibubarbie:BAAANQAECgMIBgAAAA==.Malystron:BAAANQADCggIEAAAAA==.Marollus:BAAANQABCgYICwAAAA==.Materesa:BAAANQAECgUJCgAAAA==.Maysty:BAAANQAECgUJCgAAAA==.',
Me='Meiyuki:BAAANQADCgQIBAAAAA==.Menapaws:BAABNQAECoEhAAIRAAkK1CN+DAA6AwARAAkK1CN+DAA6AwAAAA==.Meriel:BAAANQADCgYJBgAAAA==.',
Mi='Midouri:BAAANQADCgMJAwAAAA==.Milk:BAAANQADCgUIBQAAAA==.',
Mo='Moonbayne:BAAANQAECgUIDwAAAA==.Mooszer:BAAANQADCgYIBgAAAA==.Moritz:BAAANQAECgUIDAAAAA==.Motomoto:BAAANQAECggIEQAAAA==.',
Ms='Ms:BAABNQAECoEbAAILAAkK0xaxOACDAgALAAkK0xaxOACDAgAAAA==.',
Mu='Muffinmon:BAAANQAECgEIAQAAAA==.Mushinx:BAAANQADCgMJBQAAAA==.',
Na='Nasta:BAAANQAECgcIDAAAAA==.',
Ne='Nepharim:BAAANQAECgMJBQAAAA==.Nephlim:BAABNQAECoEgAAMSAAkKSiNMBgBLAwASAAkKgiFMBgBLAwAOAAgKSiIVXQAAAQAAAA==.',
Oa='Oakenmuffin:BAAANQABCgIIAgAAAA==.Oatie:BAAANQAECgQIBQAAAA==.',
Ob='Oberoñ:BAAANQADCgMIAwAAAA==.',
Om='Om:BAAANQAECgEJAQAAAA==.',
Oo='Oorlian:BAAANQADCggIHgAAAA==.',
Pa='Pantoprazole:BAAANQADCgYIAwAAAA==.Pastor:BAAANQADCgYIBwABNQADCgUIBQAEAAAAAA==.Patramia:BAAANQABCgYJBgAAAA==.Pawtyanimal:BAAANQAECgMJBgAAAA==.',
Po='Pocketbible:BAAANQAECgQJBgAAAA==.Pogo:BAAANQAECgQJBwAAAA==.Pongmo:BAAANQAECgQIDAAAAA==.',
Pu='Punchaurbuns:BAAANQABCgQJBAAAAA==.',
Py='Pyylot:BAAANQAECgEIAQAAAA==.',
Ra='Ramuel:BAAANQAECgMJBwAAAA==.Rastapopulos:BAAANQAECgMIAwAAAA==.Razhul:BAAANQABCgIIAgAAAA==.',
Re='Reaver:BAAANQAECgQICwAAAA==.Reg:BAAANQAECgQIBQAAAA==.',
Ri='Rikaku:BAAANQADCggIHgAAAA==.',
Ro='Rosemery:BAAANQAECgIJAgAAAA==.',
Ru='Ru:BAAANQAECgQIBgAAAA==.',
['Râ']='Râpodac:BAAANQAECgUIDAAAAA==.',
Sa='Sangwin:BAAANQADCgEIAQAAAQ==.Sapheluna:BAAANQABCgEIAQAAAA==.',
Sc='Schizo:BAAANQAECgEIAQABNQAECgkJGwALANMWAA==.',
Se='Selistira:BAAANQABCgMIAQAAAA==.Semdorii:BAAANQAECgUICgAAAA==.Sephywrath:BAAANQAECgUJCwAAAA==.Serabignite:BAAANQADCgIIAgABNQAECggIIAATANYfAA==.Seralith:BAABNQAECoEWAAMSAAgKLR0mFgBjAgASAAcK/x0mFgBjAgAOAAUKoBP1UwAsAQAAAA==.Seranight:BAABNQAECoEgAAMTAAgK1h9/FAC9AgATAAgK1h9/FAC9AgASAAUK0AKZUQCgAAAAAA==.Seven:BAAANQAECgUJBwABNQADCgIIAgAEAAAAAA==.Sevenpaws:BAAANQAECgQIBgABNQAECggIGgACAAUhAA==.',
Sh='Shadowchi:BAAANQAECgEIAQAAAA==.Shaolinmonk:BAAANQAECgMIBgAAAA==.Shirohige:BAAANQADCggIHgAAAA==.Shådôw:BAAANQADCgUJBgABNQAECgkJFgAGAEUdAA==.',
Si='Sicarius:BAAANQADCgEJAQAAAA==.Silvanoshi:BAAANQADCgIJAgABNQADCgcICgAEAAAAAA==.',
Sk='Skaïlar:BAAANQADCgEIAQAAAA==.',
Sn='Snayre:BAAANQADCgIJAgAAAA==.Snipêr:BAAANQADCggIDgAAAA==.',
So='Soularis:BAAANQADCgYJBgAAAA==.',
Sp='Spybro:BAAANQADCgcJDwAAAA==.',
St='Stalkingwolf:BAAANQADCgcJFgAAAA==.Stéàlth:BAAANQADCggICwABNQAECgkJFgAGAEUdAA==.',
Su='Sunrisewood:BAAANQADCgMJBQAAAA==.Suzuya:BAAANQADCgYICwAAAA==.',
Sy='Sylailia:BAAANQAECgYIDwAAAA==.Synistir:BAAANQADCgUIDAAAAA==.Syrø:BAAANQAECgQJBQAAAA==.',
Ta='Tanyon:BAAANQADCgYIBgAAAA==.Tarlynna:BAAANQADCggJGQAAAA==.',
Tc='Tcalin:BAAANQAECgMIAwAAAA==.',
Th='Thammer:BAAANQAECgIJAgAAAA==.Throndor:BAAANQADCggICQAAAA==.Thundarah:BAAANQADCgYIDgAAAA==.',
Ti='Tiarcis:BAAANQAECgYJCwAAAA==.',
To='Toughgirlone:BAAANQADCgIIAgAAAA==.',
Tr='Treesummoner:BAABNQAECoEeAAQJAAgKSSHkBAC3AgAJAAcKhSHkBAC3AgAIAAEKqR8j1ABdAAAUAAEKuQKAJgAgAAAAAA==.Triton:BAABNQAECoEZAAIGAAgKMh+YIgDcAgAGAAgKMh+YIgDcAgAAAA==.Trizuke:BAAANQADCgQIBQAAAA==.',
Tu='Tutsee:BAAANQADCgUJBQAAAA==.',
Va='Valeyka:BAAANQAECgQIBAAAAA==.Vali:BAAANQADCggICAAAAA==.Valle:BAAANQAECgIJAgAAAA==.Vasilia:BAAANQAECgMJBgAAAA==.',
Ve='Velanna:BAAANQAECgIIAgAAAA==.Veliatt:BAAANQAECgUICQAAAA==.Vexaris:BAABNQAECoEkAAIVAAkKtBmZAgDUAgAVAAkKtBmZAgDUAgAAAA==.',
Vi='Viradi:BAAANQADCgcIDwAAAA==.',
Wa='Wagonburner:BAAANQAECgEJAQAAAA==.',
Wu='Wulfbayne:BAAANQADCgMIAwAAAA==.',
Xa='Xalatoes:BAAANQAECgEIAQAAAA==.',
Xi='Xianfei:BAAANQAECgcJEwAAAA==.',
Za='Zachxd:BAAANQAECgMIBwABNQAECgkJGwALANMWAA==.Zanthe:BAAANQADCgcJFQAAAA==.Zappletree:BAAANQADCgQIBAAAAA==.Zarilice:BAAANQADCgEIAgABNQAECggIFgASAC0dAA==.',
Zh='Zhanblood:BAAANQAECgQIBgABNQAECgQJCQAEAAAAAA==.Zhanbrew:BAAANQAECgQJCQAAAA==.',
Zi='Zipit:BAABNQAECoEYAAIJAAgKjhIqCgA3AgAJAAgKjhIqCgA3AgAAAA==.',
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
