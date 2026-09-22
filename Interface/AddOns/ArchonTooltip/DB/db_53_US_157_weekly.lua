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

local lookup = {'Unknown-Unknown','Mage-Arcane','Monk-Windwalker','Druid-Balance','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Warrior-Arms','Shaman-Enhancement','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Paladin-Holy','DemonHunter-Devourer','Priest-Discipline','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Shaman-Elemental','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Shaman-Restoration','DeathKnight-Blood',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaralia:BAAANQAECgUIDAAAAA==.',
Ab='Abyssdark:BAAANQAECggJEwAAAA==.',
Ac='Accusation:BAAANQAECgcICAAAAA==.',
Ak='Akadeus:BAAANQADCggICgAAAA==.',
Al='Alarielle:BAAANQAECgMIAwABNQAECgYIDwABAAAAAA==.Altx:BAAANQABCgUIAwAAAA==.',
Am='Amirah:BAAANQADCgEIAgAAAA==.Ammathael:BAAANQAECgEJAQAAAA==.',
An='Anamarie:BAAANQAECgQJBQAAAA==.',
Ar='Aramist:BAAANQADCgQICAAAAA==.Arroy:BAAANQADCgcIDwAAAA==.',
As='Ashikahammer:BAAANQAECgYIDAABNQAECgkJGgACAB4fAA==.',
Az='Azraeth:BAAANQADCgIJAgABNQAECgEJAQABAAAAAA==.',
Ba='Baehyun:BAAANQAECggIDQABNQAFFAYIDwADAIUjAA==.Basou:BAAANQADCggICAAAAA==.',
Be='Belanova:BAAANQADCgQIBAAAAA==.',
Bl='Bloodbeard:BAAANQAECgUJBgAAAA==.Bloodedge:BAAANQADCgIIAgAAAA==.',
Bo='Bohmbear:BAAANQADCgYIBgAAAA==.',
Br='Brentobox:BAAANQAECgEJAgAAAA==.Brugara:BAAANQADCgUICQAAAA==.',
Ca='Camael:BAAANQAECgIIBQAAAA==.Cannelle:BAAANQADCgcJCgAAAA==.Carden:BAAANQAECgEIAgAAAA==.',
Ce='Cervantes:BAAANQADCgcIHAAAAA==.',
Ch='Chardr:BAACNQAFFIEKAAIEAAUKohK7BQChAQAEAAUKohK7BQChAQA1AAQKgRsAAgQACAr4JHsPABUDAAQACAr4JHsPABUDAAAA.Chillywillie:BAAANQAECgEJAQAAAA==.Chrodne:BAAANQADCgUIDQAAAA==.Chucknorrîs:BAAANQADCggIDgAAAA==.',
Cl='Clintbarton:BAABNQAECoEjAAIFAAYKrg/KKgBqAQAFAAYKrg/KKgBqAQAAAA==.',
Cr='Crûtch:BAAANQADCggJDgAAAA==.',
Ct='Cthullu:BAAANQADCggICAAAAA==.',
Cu='Culebra:BAABNQAECoEXAAMGAAgKGxB8GwALAgAGAAgKGxB8GwALAgAHAAEK/wfYQAA1AAAAAA==.',
['Cø']='Cøldshoulder:BAAANQAECgUICQAAAA==.',
Da='Daehyun:BAAANQAECggIBwABNQAFFAYIDwADAIUjAA==.Danceofdeath:BAAANQAECgEIAQABNQAECggIGwAIAHkeAA==.Dane:BAAANQAECgYJDQAAAA==.Darcmatter:BAAANQAECgcJEQAAAA==.',
De='Deadtrap:BAAANQABCggJDQAAAA==.Deathsend:BAAANQADCgYICAAAAA==.Deepsicks:BAABNQAECoEXAAIJAAkKpxYSCACrAgAJAAkKpxYSCACrAgAAAA==.Deepstate:BAAANQADCgYIGAAAAA==.Demonäde:BAAANQADCgUIAgAAAA==.',
Di='Dima:BAAANQAECgYIEAAAAA==.Dithy:BAAANQADCgcIHgAAAA==.',
Dk='Dkrmk:BAAANQADCgMIAgAAAA==.Dktelli:BAAANQADCggICAAAAA==.',
Dn='Dne:BAAANQADCggICAABNQAECgYJDQABAAAAAA==.',
Do='Donavon:BAAANQAECgQIBgAAAA==.Donutjelly:BAAANQAECgMIBwAAAA==.Dornnbryda:BAAANQADCggIDgABNQAECgUICAABAAAAAA==.',
Dr='Drackothyr:BAAANQAECgUJCAAAAA==.Dreamweavver:BAAANQADCgQIBAAAAA==.Drumark:BAAANQADCgMJAwAAAA==.',
Dw='Dwastring:BAAANQAECgMJAwAAAA==.',
Dy='Dyrale:BAAANQADCgYJFgAAAA==.',
Ek='Eknivar:BAAANQADCgQIBAABNQAECgYIEAABAAAAAA==.',
Er='Erebus:BAAANQAECgQIBAAAAA==.Erragorn:BAAANQAECgEIAgAAAA==.',
Ev='Evisa:BAAANQADCggIFAAAAA==.Evokholio:BAAANQAECgEIAQAAAA==.',
['Eö']='Eöath:BAAANQAECgEIAQAAAA==.',
Fa='Falaurenta:BAAANQADCgMIBgAAAA==.',
Fe='Feidao:BAAANQADCggJIwAAAA==.Feralith:BAAANQADCgMIAQAAAA==.',
Fo='Foshizzle:BAAANQABCgIIAgAAAA==.',
['Fë']='Fëânòr:BAAANQADCgUIBQAAAA==.',
Ga='Gailinn:BAAANQAECgQIBgAAAA==.',
Go='Gorash:BAAANQAECgEJAQAAAA==.',
Gr='Greggdshami:BAAANQAECgUJCwAAAA==.',
Gu='Gundamus:BAAANQADCgYIBgAAAA==.',
He='Healmonger:BAABNQAECoEbAAMKAAkKQRvCFADaAgAKAAkKQRvCFADaAgALAAEKwQB7ZQAOAAAAAA==.Heruin:BAAANQAECgYICwAAAA==.',
Hi='Hictor:BAAANQADCgMIAwAAAA==.',
Ho='Holly:BAAANQADCgEIAQAAAA==.Horse:BAACNQAFFIEKAAIKAAUKAQHNCQBKAQAKAAUKAQHNCQBKAQA1AAQKgSoAAgoACQonC21AAOUBAAoACQonC21AAOUBAAAA.Hourzero:BAAANQAECgEIAQAAAA==.',
Ia='Iammyscars:BAABNQAECoEYAAIMAAkKfh0zDAABAwAMAAkKfh0zDAABAwAAAA==.',
Ic='Icu:BAAANQAECgUIBQAAAA==.',
Il='Ilovecheetos:BAAANQADCggJDgAAAA==.',
Ja='Jasnahh:BAAANQAECgQICQABNQAECgYICgABAAAAAA==.Jaylas:BAAANQADCgEIAQABNQAECgcJIwANAKUeAA==.',
Jo='Joeexotíc:BAAANQADCgUIBQAAAA==.',
Ju='Jun:BAACNQAFFIEKAAIMAAUK7CSaAQAeAgAMAAUK7CSaAQAeAgA1AAQKgSoAAwwACQqtJkUAAAgEAAwACQqtJkUAAAgEAA4ACAqlIvoOAMcCAAAA.',
Ka='Kasumaus:BAAANQAECgQJBQAAAA==.',
Ke='Kelly:BAAANQADCggICAAAAA==.Kennifer:BAAANQADCggICQAAAA==.Kenshindune:BAAANQADCgQIBAAAAA==.Keragan:BAAANQADCgEJAQAAAA==.',
Kh='Khalyeesi:BAAANQADCgIIAwAAAA==.Khandris:BAAANQABCgcIEAAAAA==.Khazjek:BAAANQADCgYICAAAAA==.Khephris:BAAANQAECgYIDwAAAA==.',
Kn='Knivex:BAAANQAECgYIEAAAAA==.',
Ko='Koryann:BAAANQAECgUIDwAAAA==.Kova:BAAANQAECgEIAgAAAA==.',
Kw='Kwarthil:BAAANQABCgEIAQAAAA==.',
Ky='Kyrise:BAAANQAECgcJBwAAAA==.',
La='Lambo:BAAANQAECgQJBAAAAA==.Landam:BAAANQADCggIIAAAAA==.',
Le='Leap:BAAANQADCgMIAwABNQAECgYIDwABAAAAAA==.',
Li='Lifeaura:BAACNQAFFIEKAAIPAAUKDg5+AACiAQAPAAUKDg5+AACiAQA1AAQKgSoAAg8ACQptHFUBAAYDAA8ACQptHFUBAAYDAAAA.Lightbläster:BAAANQAECgIIBAAAAA==.Lightrider:BAAANQADCgYICwAAAA==.Linesta:BAAANQADCgEIAQAAAA==.Lionroar:BAACNQAFFIEFAAIQAAMK2yBCBAAnAQAQAAMK2yBCBAAnAQA1AAQKgSEAAhAACQp3I9UCAHUDABAACQp3I9UCAHUDAAAA.Littleguy:BAAANQAECgQIBgAAAA==.',
Ll='Llaothtaed:BAAANQAECggIBgAAAA==.',
Lo='Lochannis:BAAANQADCggIEAAAAA==.Lokalock:BAAANQAECgQIBAABNQAECgkJJAAJAFsfAA==.Lonee:BAAANQADCgIIAgAAAA==.Lorellei:BAAANQAECgEJAgAAAA==.',
Lu='Luxus:BAAANQADCgIJAgAAAA==.',
['Lâ']='Lân:BAAANQAECgEIAQABNQABCgIIAgABAAAAAA==.',
Ma='Manticor:BAAANQADCgcIBgAAAA==.Martyglaive:BAAANQAECgUJCgAAAA==.Matteas:BAAANQAECgUICgAAAA==.',
Me='Menionblue:BAAANQADCgUIBQAAAA==.Mew:BAAANQAECgQJCAAAAA==.',
Mf='Mfdoom:BAABNQAECoEiAAQRAAkKuhl2KACBAgARAAgKIhp2KACBAgASAAMKaxPfNgDDAAATAAIK/Rm6FACAAAABNQADCgIIAgABAAAAAA==.',
Mi='Mizrey:BAAANQAECggIAQAAAA==.',
Mo='Mograins:BAABNQAECoEbAAMSAAgK/x8PCwAnAgASAAYKwyAPCwAnAgARAAUKDB31YwCcAQAAAA==.Monzcarro:BAAANQADCggICwAAAA==.Morgainne:BAAANQADCgcJHgAAAA==.Mortmor:BAAANQAECgUJBQAAAA==.',
Mu='Muffinn:BAABNQAECoEVAAIUAAYKzAmqegB+AQAUAAYKzAmqegB+AQAAAA==.',
My='Mymdos:BAABNQAECoEdAAIIAAkKeB6jHQAHAwAIAAkKeB6jHQAHAwABNQABCgIJAgABAAAAAA==.Myrmidonn:BAAANQADCgYICgAAAA==.',
['Mä']='Mästérdòn:BAAANQADCgMIAwAAAA==.',
['Må']='Måsterdon:BAAANQAECgQICAAAAA==.',
['Mô']='Môiraine:BAAANQAECgEIAQAAAA==.',
Ne='Nercos:BAAANQAECgEIAQABNQAFFAIJAgABAAAAAA==.Nercqt:BAAANQAFFAIJAgAAAA==.Neverborn:BAAANQAECgQICAAAAA==.',
Ni='Niame:BAAANQAECgIIAgAAAA==.Nitraina:BAAANQAECgMJBgAAAA==.Niyabelle:BAAANQAECgYIDwAAAA==.',
No='Noggenfloggr:BAAANQAECgIIAgAAAA==.',
Ny='Nyxth:BAAANQABCggICAAAAA==.',
Od='Odïn:BAAANQADCgYIBwAAAA==.',
Ol='Oleevia:BAAANQAECgcIEwAAAA==.',
Om='Omgdingers:BAAANQAECgYICAAAAA==.',
On='Oneshót:BAAANQADCgYICAABNQAECgcICgABAAAAAA==.Oneth:BAAANQADCgcIGwAAAA==.',
Or='Oraxia:BAAANQAECgEIAQABNQAECgUJBgABAAAAAA==.Orgdynamite:BAAANQAECgEJAQABNQAFFAUICgAVABkQAA==.Orgsham:BAACNQAFFIEKAAIVAAUKGRBBBQCNAQAVAAUKGRBBBQCNAQA1AAQKgSoAAxUACQpkI1MGAJsDABUACQpkI1MGAJsDAAkAAQprDvQjAEkAAAAA.',
Pa='Paedragon:BAAANQADCgMIAwABNQADCgcIGwABAAAAAA==.Paladareian:BAABNQAECoEjAAINAAcKpR5pIwCEAgANAAcKpR5pIwCEAgAAAA==.',
Pe='Pej:BAACNQAFFIEKAAQWAAUKqRIdBQDsAAAWAAMKXxAdBQDsAAAXAAIK5QTmDACPAAAYAAEKMwn8BQBMAAA1AAQKgS0ABBYACQp5HiEJAKICABYACAqJHyEJAKICABcABAoiEqQmAPkAABgAAgrnGe4PAK0AAAAA.Pejbolt:BAAANQADCgcICgABNQAFFAUICgAMAOwkAA==.',
Ph='Phoenixa:BAAANQAECgEIAQAAAA==.',
Pl='Plus:BAAANQAECgcJCwAAAA==.',
Po='Powerslavé:BAABNQAECoEbAAIIAAgKeR60NACVAgAIAAgKeR60NACVAgAAAA==.',
Pr='Priestitoot:BAAANQADCgYICwAAAA==.',
Pu='Pumkinhead:BAAANQAECggJEwAAAA==.',
Py='Pyromania:BAAANQAECgIIAgABNQAECgQJBQABAAAAAA==.',
['Pä']='Pä:BAAANQADCgMIAQAAAA==.',
Ra='Raiden:BAAANQAECgQJCAAAAA==.Rat:BAAANQABCgIIAgAAAA==.',
Re='Revoker:BAAANQADCgQJBAABNQAECgYJEwABAAAAAA==.',
Ro='Rogi:BAAANQADCgIJAgABNQABCgIJAgABAAAAAA==.',
['Rö']='Römana:BAAANQAECgQJCAAAAA==.',
Sa='Saliva:BAAANQADCggICAAAAA==.Sanguinaris:BAAANQAECgEIAQABNQAECgEJAQABAAAAAA==.Sareya:BAAANQABCgYIDgAAAA==.Satyrical:BAAANQAECgQJCgAAAA==.',
Sc='Scorch:BAAANQAECgUICgAAAA==.',
Se='Selatha:BAAANQABCgIIAgABNQAECgkJHAACACQjAA==.Selystine:BAAANQADCgUICAAAAA==.Semaj:BAAANQADCgcIBwAAAA==.',
Sh='Shamwowolio:BAAANQAECgcIEwAAAA==.Shayd:BAAANQAECgYJEwAAAA==.Shirokyu:BAAANQADCggICAAAAA==.Shirraz:BAAANQAECgMJBAAAAA==.Shroomicide:BAAANQAECggIBgAAAA==.',
Si='Sicaris:BAAANQADCgQIBAABNQAECgUIDQABAAAAAA==.Sicksdeep:BAABNQAECoEdAAIIAAgK/hReVgAUAgAIAAgK/hReVgAUAgAAAA==.Sigürd:BAAANQADCgEIAQAAAA==.Silverstorm:BAAANQADCgYIBgAAAA==.',
Sk='Skÿe:BAAANQAECgUJCwAAAA==.',
Sl='Slamma:BAACNQAFFIEJAAIIAAUK6CLKAwAJAgAIAAUK6CLKAwAJAgA1AAQKgS4AAggACQpNJrIBAOcDAAgACQpNJrIBAOcDAAAA.Slappinbubs:BAAANQAECgEJAQAAAA==.Slicedbreád:BAACNQAFFIEIAAMZAAUKSwzyBwAsAQAZAAQK6QXyBwAsAQAVAAIKjRwRDwCtAAA1AAQKgScAAxkACQrCGFEqAFgCABkACQrCGFEqAFgCABUAAQq6IkXAAGYAAAE1AAQKAQgBAAEAAAAA.',
Sm='Smokadaganga:BAAANQAECgcJDgAAAA==.',
So='Sols:BAAANQAECgQIBAABNQAECggIGwAIAHkeAA==.Sondirion:BAAANQAECgUICAAAAA==.Sowet:BAAANQADCgcIBwAAAA==.',
Sp='Speoghii:BAAANQAECgQIDAAAAA==.Spifftreebug:BAAANQAECgUJCwAAAA==.Sprinklez:BAAANQAECgQJBAAAAA==.',
St='Steelerschic:BAAANQADCggIIQAAAA==.Stormleader:BAAANQAECggIEgAAAA==.',
Su='Surge:BAAANQADCggIHAAAAA==.',
Ta='Tai:BAAANQAECgUJCwAAAA==.Tainema:BAAANQAECgIIBAAAAA==.Tankguywowie:BAAANQAECgUIBQABNQAECggJEAABAAAAAA==.Taurriel:BAAANQAECgUICgAAAA==.Tazzm:BAAANQAECgYIDwAAAA==.',
Te='Teranok:BAAANQAECgYICQAAAA==.Terzal:BAAANQADCgYIBgAAAA==.',
Th='Thalel:BAAANQAECgQIBgAAAA==.Theacused:BAAANQAECgYICQABNQAECgcICAABAAAAAA==.Thoir:BAACNQAFFIEKAAIZAAUKDSXGAQAjAgAZAAUKDSXGAQAjAgA1AAQKgSoAAhkACQplJSoDAJ8DABkACQplJSoDAJ8DAAE1AAUUBQgKAAoAAQEA.Thorodinson:BAAANQAECgMJAwAAAA==.',
Ti='Tipsylorcet:BAAANQAECgUJCAAAAA==.',
Tk='Tkrain:BAAANQADCgQICAAAAA==.',
Tr='Trashbull:BAAANQAECggJAgAAAA==.Tricktickler:BAAANQADCgcIFwAAAA==.Troy:BAAANQADCgUIBQAAAA==.',
Tu='Tuskani:BAAANQABCggIDwAAAA==.',
Ty='Tybird:BAAANQAECgUJDAAAAA==.',
Ul='Ulsull:BAAANQADCgcIEAAAAA==.Ulyssi:BAACNQAFFIEKAAILAAUKtBdPAgDPAQALAAUKtBdPAgDPAQA1AAQKgSoAAgsACQoNIsoDAIgDAAsACQoNIsoDAIgDAAAA.',
Um='Ummpatas:BAAANQAECgEIAQAAAA==.',
['Uñ']='Uñàble:BAAANQADCgIIAgAAAA==.',
Va='Valymus:BAAANQADCgIIAgABNQAECgYJEwABAAAAAA==.Vandagylon:BAAANQADCgYIDAAAAA==.Vandals:BAAANQAECgUJDgAAAA==.',
Ve='Ven:BAAANQAECgUJCAAAAA==.',
Vo='Voltaire:BAAANQADCgIIAgAAAA==.',
Wa='Walle:BAAANQADCgEIAQAAAA==.Wankstar:BAAANQAECgEIAQAAAA==.Warvein:BAAANQAECgMJAwAAAA==.',
We='Weehunt:BAAANQAECgUJBwAAAA==.',
Wh='Whillia:BAAANQADCgMIAwAAAA==.',
Wi='Wicah:BAAANQAECgIIAwAAAA==.Wicka:BAAANQAECgUJDQAAAA==.Widowblade:BAAANQAECgEIAQAAAA==.Wildriver:BAAANQAECgQIBQAAAA==.',
Xa='Xaehyun:BAACNQAFFIEPAAIDAAYKhSOnAQAQAgADAAYKhSOnAQAQAgA1AAQKgRkAAgMACQrfJhAJAPsCAAMACQrfJhAJAPsCAAAA.Xandrelar:BAAANQADCggIDQABNQAECgYJEwABAAAAAA==.',
Xm='Xmrpdk:BAACNQAFFIEKAAIaAAUKCh0aBAC8AQAaAAUKCh0aBAC8AQA1AAQKgSoAAhoACQo1JDEDAKkDABoACQo1JDEDAKkDAAAA.Xmrppally:BAAANQADCgQIBAABNQAFFAUICgAaAAodAA==.',
Xy='Xy:BAAANQADCggICAAAAA==.',
Ya='Yarina:BAAANQADCgUIBQAAAA==.',
Yo='Yoyiek:BAAANQAECggJEAAAAA==.',
Za='Zalynn:BAAANQAECgEIAQAAAA==.Zanne:BAABNQAECoEcAAIFAAgKUB6dEACjAgAFAAgKUB6dEACjAgAAAA==.Zarthul:BAAANQAECgEIAgAAAA==.',
Ze='Zehara:BAAANQADCgMJAwAAAA==.',
Zh='Zhenyu:BAAANQADCgQIBAABNQAECgEJAQABAAAAAA==.',
Zl='Zlot:BAECNQAFFIEKAAMUAAUKOhkaCAAOAQAUAAMK+RsaCAAOAQAFAAIKGhVDDgCoAAA1AAQKgSoAAxQACQr1ImseAMUCABQABwr5I2seAMUCAAUABwoZHXAcAA8CAAAA.',
Zu='Zulani:BAAANQADCgIIAgAAAA==.',
['Õn']='Õneshot:BAAANQAECgcICgAAAA==.',
['Øñ']='Øñêshot:BAAANQADCggIEwABNQAECgcICgABAAAAAA==.',
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
