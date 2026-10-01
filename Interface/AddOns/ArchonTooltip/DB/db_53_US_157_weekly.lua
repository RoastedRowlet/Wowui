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

local lookup = {'Warlock-Demonology','Mage-Frost','Unknown-Unknown','Monk-Windwalker','Druid-Balance','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Warrior-Arms','Shaman-Enhancement','Hunter-BeastMastery','Mage-Arcane','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Paladin-Holy','DemonHunter-Devourer','Priest-Discipline','Druid-Restoration','Warlock-Destruction','Warlock-Affliction','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Hunter-Survival','Shaman-Restoration','Mage-Fire','Druid-Guardian','DeathKnight-Blood',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaralia:BAAANQAECgUIDAAAAA==.',
Ab='Abyssdark:BAABNQAECoEdAAIBAAkKBhp4GgDtAgABAAkKBhp4GgDtAgAAAA==.',
Ac='Accusation:BAAANQAFFAEIAQAAAA==.',
Ak='Akadeus:BAAANQADCggICgAAAA==.',
Al='Alarielle:BAAANQAECgMIAwABNQAECgcIGgACAPgcAA==.Altx:BAAANQABCgUIAwAAAA==.',
Am='Amirah:BAAANQADCgEIAgAAAA==.Ammathael:BAAANQAECgEJAQAAAA==.',
An='Anamarie:BAAANQAECgQIBQABNQAECgYICAADAAAAAA==.',
Ar='Aramist:BAAANQADCgUIDQAAAA==.Arroy:BAAANQADCgcIDwAAAA==.',
As='Ashikahammer:BAAANQAECgYIDQABNQAECgkJIgACAHkhAA==.',
Az='Azraeth:BAAANQAECgUIBQAAAA==.',
Ba='Baehyun:BAAANQAECggIDQABNQAFFAYIDwAEAIYjAA==.Basou:BAAANQADCggICAAAAA==.',
Be='Belanova:BAAANQADCgQIBAAAAA==.Belnathas:BAAANQADCgcIEQAAAA==.',
Bl='Bloodbeard:BAAANQAECgYIBwAAAA==.Bloodedge:BAAANQADCgIIBAAAAA==.',
Bo='Bohmbear:BAAANQADCgYIBgAAAA==.',
Br='Brentobox:BAAANQAECgQIBgAAAA==.Brugara:BAAANQADCgYIDwAAAA==.',
Ca='Camael:BAAANQAECgQICQAAAA==.Cannelle:BAAANQADCggIEAAAAA==.Carden:BAAANQAECgQIBgAAAA==.',
Ce='Cervantes:BAAANQADCggIHwAAAA==.',
Ch='Chardr:BAACNQAFFIENAAIFAAYKZRRdBAAIAgAFAAYKZRRdBAAIAgA1AAQKgRsAAgUACAr4JG0UAP4CAAUACAr4JG0UAP4CAAAA.Chillywillie:BAAANQAECgEIAgAAAA==.Chrodne:BAAANQADCgcIEwAAAA==.Chucknorrîs:BAAANQAECgEIAQAAAA==.',
Ci='Cigam:BAAANQAECgEIAQAAAA==.',
Cl='Clintbarton:BAABNQAECoEpAAIGAAYKDxNZLgCAAQAGAAYKDxNZLgCAAQAAAA==.',
Cr='Crûtch:BAAANQADCggJDgAAAA==.',
Ct='Cthullu:BAAANQADCggICAAAAA==.',
Cu='Culebra:BAABNQAECoEcAAMHAAkK2xDbHABBAgAHAAkK2xDbHABBAgAIAAEKgBM9QgBJAAAAAA==.',
['Cø']='Cøldshoulder:BAAANQAECgYIDwAAAA==.',
Da='Daehyun:BAAANQAECggICwABNQAFFAYIDwAEAIYjAA==.Danceofdeath:BAAANQAECgYIBwABNQAECgkJIAAJAEoeAA==.Dane:BAAANQAECgcIEwAAAA==.Darcmatter:BAAANQAECgcIEQAAAA==.',
De='Deadtrap:BAAANQABCggIDwAAAA==.Deathsend:BAAANQADCgYICAAAAA==.Deepsicks:BAABNQAECoEZAAIKAAkKphjVCQCjAgAKAAkKphjVCQCjAgAAAA==.Deepstate:BAAANQADCgcIHwAAAA==.Demonäde:BAAANQADCgUIAgAAAA==.',
Di='Dima:BAABNQAECoEbAAILAAcKMBuQUAAvAgALAAcKMBuQUAAvAgAAAA==.Dithy:BAAANQADCggIIQAAAA==.',
Dk='Dkrmk:BAAANQADCgMIAgAAAA==.Dktelli:BAAANQAECgIIAgABNQAECgkJLAAKAG4gAA==.',
Dn='Dne:BAAANQADCggIDgABNQAECgcIEwADAAAAAA==.',
Do='Donavon:BAAANQAECgQICAAAAA==.Donutjelly:BAAANQAECgMICwAAAA==.Dornnbryda:BAAANQADCggIDgABNQAECgUIDQADAAAAAA==.',
Dr='Drackothyr:BAAANQAECgUIDAAAAA==.Dreamweavver:BAAANQADCgQIBAAAAA==.Drumark:BAAANQADCgMIAwAAAA==.',
Dw='Dwastring:BAAANQAECgUICAAAAA==.',
Dy='Dyrale:BAAANQADCgYIGwAAAA==.',
Ek='Eknivar:BAAANQADCgQIBAABNQAECggIGwAMANkbAA==.',
Er='Erebus:BAAANQAECgQIBAAAAA==.Erragorn:BAAANQAECgQICgAAAA==.',
Ev='Evisa:BAAANQAECgEIAQAAAA==.Evokholio:BAAANQAECgIIAwAAAA==.',
['Eö']='Eöath:BAAANQAECgEIAQAAAA==.',
Fa='Falaurenta:BAAANQADCgMIBgAAAA==.',
Fe='Feidao:BAAANQAECgIIAgAAAA==.Feralith:BAAANQADCgMIAQAAAA==.',
Fo='Foshizzle:BAAANQABCgIIAgAAAA==.',
['Fë']='Fëânòr:BAAANQADCgUIBQAAAA==.',
Ga='Gailinn:BAAANQAECgQICgAAAA==.',
Go='Gorash:BAAANQAECgEJAQABNQAECgUIBQADAAAAAA==.',
Gr='Greggdshami:BAAANQAECgYIEQAAAA==.',
Gu='Gundamus:BAAANQADCgYIBgAAAA==.',
He='Healmonger:BAABNQAECoElAAMNAAkK7x4+DwAjAwANAAkK7x4+DwAjAwAOAAEKwQBydgANAAAAAA==.Heruin:BAAANQAECgcIDQAAAA==.',
Hi='Hictor:BAAANQADCgMIAwAAAA==.',
Ho='Holly:BAAANQADCgEIAQAAAA==.Horse:BAACNQAFFIEPAAINAAUKFAF1DgBHAQANAAUKFAF1DgBHAQA1AAQKgTIAAg0ACQpwDKBKAPMBAA0ACQpwDKBKAPMBAAAA.Hourzero:BAAANQAECgEIAQAAAA==.',
Ia='Iammyscars:BAABNQAECoEYAAIPAAkKfh0WEgDYAgAPAAkKfh0WEgDYAgAAAA==.',
Ic='Icu:BAAANQAECgUIBQAAAA==.',
Il='Ilovecheetos:BAAANQADCggJDgAAAA==.',
Ja='Jasnahh:BAAANQAECgQICQABNQAECgYICgADAAAAAA==.Jaylas:BAAANQADCgEIAQABNQAECgcIJAAQAKUeAA==.',
Jo='Joeexotíc:BAAANQAECgcICAAAAA==.',
Ju='Jun:BAACNQAFFIEPAAIPAAUKSiWUAgAeAgAPAAUKSiWUAgAeAgA1AAQKgTIAAw8ACQrHJjYAAAsEAA8ACQrHJjYAAAsEABEACAqlIksTAKQCAAAA.Junfan:BAAANQAECggICQAAAA==.',
Ka='Kasumaus:BAAANQAECgUICgAAAA==.',
Ke='Kelly:BAAANQADCggICAAAAA==.Kennifer:BAAANQADCggICQAAAA==.Kenshindune:BAAANQADCgQIBAAAAA==.Keragan:BAAANQADCgEJAQAAAA==.',
Kh='Khalyeesi:BAAANQADCgIIAwAAAA==.Khandris:BAAANQABCggIEgAAAA==.Khazjek:BAAANQADCgYICAAAAA==.Khephris:BAABNQAECoEaAAICAAcK+BydBwAmAgACAAcK+BydBwAmAgAAAA==.',
Kn='Knivex:BAABNQAECoEbAAMMAAgK2RvChwAxAgAMAAcKChzChwAxAgACAAMKVBkZGQDlAAAAAA==.',
Ko='Koryann:BAAANQAECgUIDwAAAA==.Kova:BAAANQAECgUIBwAAAA==.',
Kw='Kwarthil:BAAANQABCgEIAQAAAA==.',
Ky='Kyrise:BAAANQAECgcIDAAAAA==.',
La='Lambo:BAAANQAECgQJBAAAAA==.Landam:BAAANQAECgMIAwAAAA==.',
Le='Leap:BAAANQADCgMIAwABNQAECggIGgARACIUAA==.',
Li='Lifeaura:BAACNQAFFIEPAAISAAUKRBOoAACmAQASAAUKRBOoAACmAQA1AAQKgTIAAhIACQpSIMUAAF4DABIACQpSIMUAAF4DAAAA.Lightbläster:BAAANQAECgIIBAAAAA==.Lightrider:BAAANQADCgYICwAAAA==.Linesta:BAAANQADCgEIAQAAAA==.Lionroar:BAACNQAFFIEIAAITAAQKKx/IBAB2AQATAAQKKx/IBAB2AQA1AAQKgSQAAhMACQp3I3cEAGEDABMACQp3I3cEAGEDAAAA.Littleguy:BAAANQAECgUICwAAAA==.',
Ll='Llaothtaed:BAAANQAECggIBgAAAA==.',
Lo='Lochannis:BAAANQADCggIEAAAAA==.Lokalock:BAAANQAECgQIBAABNQAECgkJLAAKAG4gAA==.Lonee:BAAANQADCgIIAgAAAA==.Lorellei:BAAANQAECgQIBgAAAA==.Lothgow:BAAANQAECgEIAgAAAA==.',
Lu='Luxus:BAAANQADCgIJAgAAAA==.',
['Lâ']='Lân:BAAANQAECgEIAQABNQABCgIIAgADAAAAAA==.',
Ma='Maelynn:BAAANQADCgUIBQAAAA==.Manticor:BAAANQADCgcIBgAAAA==.Martyglaive:BAAANQAECgYIDgAAAA==.Matteas:BAAANQAECgYIEAAAAA==.',
Me='Menionblue:BAAANQADCgUIBQAAAA==.Mew:BAAANQAECgQICgAAAA==.',
Mf='Mfdoom:BAABNQAECoEmAAQBAAkK8BrGMgCDAgABAAgKmBvGMgCDAgAUAAMKaxNAPAC8AAAVAAIK/RnuGAB8AAABNQADCgIIBAADAAAAAA==.',
Mi='Mizrey:BAAANQAECggICQAAAA==.',
Mo='Mograins:BAABNQAECoEjAAMUAAgKaSDuCwAlAgAUAAYKUCHuCwAlAgABAAUKDB3AewCUAQAAAA==.Monzcarro:BAAANQADCggICwAAAA==.Mordar:BAAANQADCgQIBAAAAA==.Morgainne:BAAANQADCggIIQAAAA==.Mortmor:BAAANQAECgYICwAAAA==.',
Mu='Muffinn:BAABNQAECoEbAAILAAYKnwq8kwB7AQALAAYKnwq8kwB7AQAAAA==.Mursê:BAAANQAECgMIAwAAAA==.',
My='Mymdos:BAABNQAECoEmAAIJAAkK1B8nGwAtAwAJAAkK1B8nGwAtAwABNQABCgIJAgADAAAAAA==.Myrmidonn:BAAANQADCgYICgAAAA==.',
['Mä']='Mästérdòn:BAAANQAECgEIAQAAAA==.',
['Må']='Måsterdon:BAAANQAECgQIDAAAAA==.',
['Mô']='Môiraine:BAAANQAECgEIAQAAAA==.',
Ne='Nercos:BAAANQAECgEIAQABNQAFFAIIAgADAAAAAA==.Nercqt:BAAANQAFFAIIAgAAAA==.Neverborn:BAAANQAECgQICwAAAA==.',
Ni='Niame:BAAANQAECgQIBgAAAA==.Nitraina:BAAANQAECgQIDwAAAA==.Niyabelle:BAAANQAECgYIEwAAAA==.',
No='Noggenfloggr:BAAANQAECgUIBwAAAA==.',
Ny='Nyxth:BAAANQABCggIDAAAAA==.',
Od='Odïn:BAAANQADCgYIBwAAAA==.',
Ol='Oleevia:BAABNQAECoEcAAIOAAgKuBMuHAAaAgAOAAgKuBMuHAAaAgAAAA==.',
Om='Omgdingers:BAAANQAECgYICAABNQAECggICwADAAAAAA==.',
On='Oneshót:BAAANQADCgYICAABNQAECgcIDgADAAAAAA==.Oneth:BAAANQADCggIHgAAAA==.',
Or='Oraxia:BAAANQAECgEIAQABNQAECgYIBwADAAAAAA==.Orgdynamite:BAAANQAECgQIBQABNQAFFAUIDwAWADoVAA==.Orgsham:BAACNQAFFIEPAAIWAAUKOhVWBwCfAQAWAAUKOhVWBwCfAQA1AAQKgS4AAxYACQq2Iz4IAJQDABYACQq2Iz4IAJQDAAoAAQprDqooAEgAAAAA.',
Pa='Paedragon:BAAANQADCgMIAwABNQADCggIHgADAAAAAA==.Paimon:BAAANQADCgYIBgAAAA==.Paladareian:BAABNQAECoEkAAIQAAcKpR7HLAB7AgAQAAcKpR7HLAB7AgAAAA==.',
Pe='Pej:BAACNQAFFIEPAAQXAAUKIBN6BQAfAQAXAAQKyw16BQAfAQAYAAQK+QngAwAbAQAZAAIK5QRKEACMAAA1AAQKgTUABBcACQqNHkgLAIUCABcACAqJH0gLAIUCABkABwpPFxsXABECABgABApaHDILAFcBAAAA.Pejbolt:BAAANQADCgcICgABNQAFFAUIDwAPAEolAA==.',
Ph='Phoenixa:BAAANQAECgEIAQAAAA==.',
Pl='Plus:BAAANQAECgcICwAAAA==.',
Po='Powerslavé:BAABNQAECoEgAAIJAAkKSh6AKwDhAgAJAAkKSh6AKwDhAgAAAA==.',
Pr='Priestitoot:BAAANQADCgYICwAAAA==.',
Pu='Pumkinhead:BAAANQAECggIEwAAAA==.',
Py='Pyromania:BAAANQAECgYICAAAAA==.',
['Pä']='Pä:BAAANQADCgMIAQAAAA==.',
Ra='Raiden:BAAANQAECgUIDgAAAA==.Rat:BAAANQABCgIIAgAAAA==.',
Re='Rentacat:BAAANQADCggICAAAAA==.Retropâlly:BAAANQADCgMIAwAAAA==.Revoker:BAAANQADCgQJBAABNQAECggIHQAaAOEaAA==.',
Ro='Rogi:BAAANQADCgIJAgABNQABCgIJAgADAAAAAA==.',
['Rö']='Römana:BAAANQAECgYIDgAAAA==.',
Sa='Saliva:BAAANQADCggICAAAAA==.Sanguinaris:BAAANQAECgEIAQABNQAECgUIBQADAAAAAA==.Sareya:BAAANQABCgYIDgAAAA==.Sataanic:BAAANQAECgIIAgAAAA==.Satyrical:BAAANQAECgUIDwAAAA==.',
Sc='Scorch:BAAANQAECgYIEAAAAA==.',
Se='Sedrayn:BAAANQAECgEIAQAAAA==.Selatha:BAAANQABCgIIAgABNQAFFAMIBwAMALMbAA==.Selystine:BAAANQADCgUICAAAAA==.Semaj:BAAANQADCgcIBwAAAA==.',
Sh='Shamwowolio:BAABNQAECoEdAAIWAAgKghAYTwDrAQAWAAgKghAYTwDrAQAAAA==.Shayd:BAABNQAECoEdAAQaAAgK4Rq8AwB/AgAaAAgKGxa8AwB/AgALAAcKYhqKUQAsAgAGAAEKyQ5raQA5AAAAAA==.Shirokyu:BAAANQADCggICAAAAA==.Shirra:BAAANQADCgcIBwAAAA==.Shirraz:BAAANQAECgMIBQAAAA==.Sho:BAAANQABCgYICAAAAA==.Shroomicide:BAAANQAECggIBgAAAA==.',
Si='Sicaris:BAAANQADCgYICgABNQAECggIEQADAAAAAA==.Sicksdeep:BAABNQAECoEgAAIJAAkKGhX3VQBGAgAJAAkKGhX3VQBGAgAAAA==.Sigürd:BAAANQADCgEIAQAAAA==.Silverstorm:BAAANQAECgIIAgAAAA==.',
Sk='Skÿe:BAAANQAECgYIEQAAAA==.',
Sl='Slamma:BAACNQAFFIEOAAIJAAUK5SP3BQAGAgAJAAUK5SP3BQAGAgA1AAQKgTQAAgkACQp3JiICAOUDAAkACQp3JiICAOUDAAAA.Slappin:BAAANQADCgEIAQAAAA==.Slappinbubs:BAAANQAECgEJAQAAAA==.Slicedbreád:BAACNQAFFIENAAMWAAUKbR9oCACEAQAWAAQKkh1oCACEAQAbAAQK6QVADAAhAQA1AAQKgSoAAxsACQp1GbE2AD4CABsACQp1GbE2AD4CABYAAwrOIxmHADsBAAE1AAQKAQgBAAMAAAAA.',
Sm='Smokadaganga:BAABNQAECoEWAAMcAAkKDQuBAwBxAQAcAAYKMA2BAwBxAQAMAAcKQQYV8QBWAQAAAA==.',
So='Sols:BAAANQAECgQICAABNQAECgkJIAAJAEoeAA==.Sondirion:BAAANQAECgUIDQAAAA==.Sowet:BAAANQADCgcIBwAAAA==.',
Sp='Speoghii:BAAANQAECgYIEgAAAA==.Spifftreebug:BAAANQAECgYIEQAAAA==.Sprinklez:BAAANQAECgQICAAAAA==.',
St='Steelerschic:BAAANQAECgIIAgAAAA==.Stormleader:BAABNQAECoEgAAMTAAkKYg2EHQDtAQATAAkKYg2EHQDtAQAdAAEK4wCITQAUAAAAAA==.',
Su='Surge:BAAANQAECgEIAQAAAA==.',
Ta='Tai:BAAANQAECgYIEQAAAA==.Tainema:BAAANQAECgIIBAAAAA==.Tankguywowie:BAAANQAECgUIBQABNQAECgkJGAAFAJgQAA==.Taurriel:BAAANQAECgYIEAAAAA==.Tazzm:BAABNQAECoEYAAIGAAcKkgPwOQAaAQAGAAcKkgPwOQAaAQAAAA==.',
Te='Teranok:BAAANQAECgYICQAAAA==.Terzal:BAAANQADCgYIBgAAAA==.',
Th='Thalel:BAAANQAECgUICgAAAA==.Theacused:BAAANQAECgYICQABNQAFFAEIAQADAAAAAA==.Thoir:BAACNQAFFIEPAAIbAAUKDSXtAgAcAgAbAAUKDSXtAgAcAgA1AAQKgTIAAhsACQrSJUEDAKEDABsACQrSJUEDAKEDAAE1AAUUBQgPAA0AFAEA.Thorodinson:BAAANQAECgMJAwAAAA==.',
Ti='Tipsylorcet:BAAANQAECgUIDAAAAA==.',
Tk='Tkrain:BAAANQADCgQICAAAAA==.',
Tr='Trashbull:BAAANQAECggIAgAAAA==.Tricktickler:BAAANQADCggIGgAAAA==.Troy:BAAANQADCgUIBQAAAA==.',
Tu='Tuskani:BAAANQABCggIDwAAAA==.',
Ty='Tybird:BAAANQAECgYIEgAAAA==.Tyranisv:BAAANQADCgMIAwAAAA==.',
Ul='Ulsull:BAAANQADCgcIEAAAAA==.Ulyssi:BAACNQAFFIEPAAIOAAUKOBpRAwDYAQAOAAUKOBpRAwDYAQA1AAQKgTIAAg4ACQqBJZABAMIDAA4ACQqBJZABAMIDAAAA.',
Um='Ummpatas:BAAANQAECgEIAQAAAA==.',
Us='Usseel:BAAANQADCgMIAwAAAA==.',
['Uñ']='Uñàble:BAAANQADCgIIAgAAAA==.',
Va='Valymus:BAAANQADCgIIAgABNQAECggIHQAaAOEaAA==.Vandagylon:BAAANQADCgYIDAAAAA==.Vandals:BAAANQAECgUJDgAAAA==.',
Ve='Ven:BAAANQAECgUIDAAAAA==.',
Vo='Voltaire:BAAANQADCgIIAgAAAA==.',
Wa='Walle:BAAANQADCgEIAQAAAA==.Wankstar:BAAANQAECgEIAQAAAA==.Warvein:BAAANQAECgcICgAAAA==.',
We='Weehunt:BAAANQAECgUICwAAAA==.Weeshami:BAAANQADCgMIAwAAAA==.',
Wh='Whillia:BAAANQADCgMIAwAAAA==.',
Wi='Wicah:BAAANQAECgIIBQAAAA==.Wicka:BAAANQAECgYIEwAAAA==.Widowblade:BAAANQAECgEIAQAAAA==.Wildriver:BAAANQAECgUICgAAAA==.',
Xa='Xaehyun:BAACNQAFFIEPAAIEAAYKhiP2AgDmAQAEAAYKhiP2AgDmAQA1AAQKgRwAAgQACQrvJlQRAJQCAAQACQrvJlQRAJQCAAAA.Xandrelar:BAAANQADCggIDQABNQAECggIHQAaAOEaAA==.',
Xm='Xmrpdk:BAACNQAFFIEPAAIeAAUKqyL/AwD9AQAeAAUKqyL/AwD9AQA1AAQKgTIAAh4ACQpEJdQBAM8DAB4ACQpEJdQBAM8DAAAA.Xmrppally:BAAANQAECgEIAQABNQAFFAUIDwAeAKsiAA==.',
Xy='Xy:BAAANQADCggICAAAAA==.',
Ya='Yarina:BAAANQADCgUIBQAAAA==.',
Yo='Yoyiek:BAABNQAECoEYAAMFAAkKmBADKwBBAgAFAAkKmBADKwBBAgAdAAMKcwJFNQBgAAAAAA==.',
Za='Zalynn:BAAANQAECgEIAQAAAA==.Zanne:BAABNQAECoEeAAIGAAkKxht3EQCyAgAGAAkKxht3EQCyAgAAAA==.Zarthul:BAAANQAECgIIBAAAAA==.',
Ze='Zehara:BAAANQADCgMJAwAAAA==.',
Zh='Zhenyu:BAAANQADCgQIBAABNQAECgUIBQADAAAAAA==.',
Zl='Zlot:BAECNQAFFIEPAAMLAAUKEBogCwAhAQALAAMKXh0gCwAhAQAGAAIKGhUQEwCeAAA1AAQKgTIAAwsACQrWJc0UAB4DAAsABwqXJs0UAB4DAAYABwqsHu8eABwCAAAA.',
Zu='Zulani:BAAANQADCgIIAgAAAA==.',
['Õn']='Õneshot:BAAANQAECgcIDgAAAA==.',
['Øñ']='Øñêshot:BAAANQADCggIEwABNQAECgcIDgADAAAAAA==.',
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
