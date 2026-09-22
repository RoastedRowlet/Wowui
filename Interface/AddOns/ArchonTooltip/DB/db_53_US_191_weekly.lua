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

local lookup = {'DeathKnight-Blood','Monk-Windwalker','Unknown-Unknown','Paladin-Protection','Evoker-Preservation','Druid-Feral','Druid-Restoration','Mage-Arcane','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Retribution','Shaman-Restoration','Rogue-Outlaw','Rogue-Assassination','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Warrior-Arms','Paladin-Holy','Shaman-Elemental','Rogue-Subtlety',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acaciastrain:BAAANQADCgcJDQAAAA==.Acedk:BAABNQAECoEaAAIBAAkKYBugFgCnAgABAAkKYBugFgCnAgAAAA==.',
Ae='Aelord:BAAANQADCgUIBQAAAA==.Aeriss:BAAANQABCgQIBAAAAA==.Aetheria:BAAANQADCgYJBgAAAA==.Aethos:BAAANQAECgQIBAABNQAECggIGQACAM8cAA==.',
Ak='Akashá:BAAANQADCgEIAQAAAA==.',
Al='Aladrius:BAEANQAECgIJAwAAAA==.Alexanderath:BAAANQAECgIIAwAAAA==.Alkatractite:BAAANQAECgEJAQAAAA==.Allenwalker:BAAANQAECgEIAQAAAA==.Allison:BAAANQADCgUIBQABNQAECgYIDwADAAAAAA==.',
An='Anelise:BAAANQADCgUIBQAAAA==.Antelon:BAAANQADCggJEAABNQAECgkJFgAEAJIMAA==.',
Ao='Aoeslave:BAAANQAECgYIEAAAAA==.',
Ap='Apk:BAAANQADCggIDwAAAA==.',
Ar='Arrisia:BAAANQADCggJFwAAAA==.Arthedain:BAAANQAECgMIAwAAAA==.Arthedaine:BAAANQAECgEIAQABNQAECgMIAwADAAAAAA==.',
As='Assano:BAAANQAECgQIBAABNQAECgYJEQADAAAAAA==.',
Au='Auvry:BAABNQAECoEaAAIFAAkKbA4/EgAxAgAFAAkKbA4/EgAxAgAAAA==.',
Az='Azurine:BAAANQADCgYIBgAAAA==.',
Ba='Bahamutfang:BAAANQAECgIJAwAAAA==.Bakala:BAAANQADCggJFwAAAA==.Barath:BAAANQAECgIJAwAAAA==.',
Be='Belegaer:BAAANQAECgQJBQAAAA==.Belenos:BAAANQADCgYICgABNQADCgYICgADAAAAAA==.Benmaverick:BAAANQAECgIIAgAAAA==.Bervin:BAAANQADCggIHAAAAA==.',
Bi='Bifftunkisjr:BAAANQADCgEJAQAAAA==.Bishop:BAAANQAECgQJBgAAAA==.',
Bo='Bobe:BAAANQAECgUIEAAAAA==.Bobedruid:BAAANQADCggIFwAAAA==.Bordok:BAAANQAECgIJAwAAAA==.Borkuz:BAAANQADCggJCAAAAA==.',
Br='Brawl:BAAANQADCgYIBgAAAA==.Brunco:BAAANQAECgYIDwAAAA==.',
Ca='Captplanet:BAABNQAECoEYAAMGAAcKgRQ4CwDHAQAGAAYKFxc4CwDHAQAHAAcKzQanJABbAQAAAA==.',
Ce='Ceindra:BAAANQAECgYIDwAAAA==.Celestria:BAAANQAECgIJAgAAAA==.Celiñ:BAAANQAECgEIAQAAAA==.Cerealkiller:BAAANQADCgYJBgAAAA==.',
Ch='Chipcho:BAAANQADCggICAAAAA==.Chuladk:BAAANQAECgEIAQAAAA==.',
Co='Constantinez:BAAANQAECggICAAAAA==.Cor:BAAANQAECgEIAQAAAA==.',
Cu='Cuddlymethod:BAAANQADCgUIBQAAAA==.',
['Có']='Cól:BAABNQAECoEcAAIIAAgKRBLedQAyAgAIAAgKRBLedQAyAgAAAA==.',
Da='Daddymoo:BAAANQADCgUIDAAAAA==.Dahealzrhere:BAAANQADCgEIAQAAAA==.Dalel:BAABNQAECoEmAAMJAAkKTxzeCwD0AgAJAAkKTxzeCwD0AgAKAAEKlhHSXwA6AAAAAA==.David:BAAANQAECgQICQAAAA==.',
De='Deadlyglow:BAAANQAECgIJAgAAAA==.Demiurgos:BAAANQAECgYIBwAAAA==.Denogarn:BAAANQADCggIEQAAAA==.Dermot:BAAANQAECgQICQAAAA==.',
Dh='Dhiying:BAAANQADCgcIBwAAAA==.',
Di='Dirtface:BAAANQAECgUICgAAAA==.Dixlongmd:BAAANQAECgEIAQAAAA==.Dixmen:BAABNQAECoEVAAILAAcKCxFZcwCjAQALAAcKCxFZcwCjAQAAAA==.',
Do='Dolemen:BAAANQAECgMIBAAAAA==.Domaon:BAAANQAECgYIEwAAAA==.Domshammy:BAAANQADCggICAABNQAECgYIEwADAAAAAA==.Doubt:BAAANQADCggJFgAAAA==.Dozy:BAAANQAECgYIDwAAAA==.',
Dr='Druidheelzz:BAAANQAECgIJAgAAAA==.Drôôdude:BAAANQADCgQIBAAAAA==.',
Du='Dunigan:BAAANQAECgQJBgAAAA==.Dunigen:BAAANQADCgYIFgAAAA==.',
Eb='Ebeast:BAAANQAECgcJDAAAAA==.',
Ev='Evianda:BAAANQADCggIEAAAAA==.',
Fa='Facade:BAAANQAECgQIBwAAAA==.Facepalm:BAAANQAECgQJBwAAAA==.Falyy:BAAANQADCgMIAwAAAA==.Farmergeorge:BAAANQAECgQJCAAAAA==.',
Fe='Fentak:BAAANQADCgcIEwAAAA==.',
Fo='Forbidenelf:BAABNQAECoEUAAILAAcKABsaUQARAgALAAcKABsaUQARAgAAAA==.Forgotmymeds:BAAANQAECgEIAQAAAA==.Foxmccloud:BAAANQADCggJFwAAAA==.',
Fr='Frosted:BAAANQADCggIAgAAAA==.Fruitloop:BAAANQAECgQJCgAAAA==.',
Fu='Funkybooty:BAAANQABCgIIAgAAAA==.Fuzybrewing:BAAANQABCgQICAAAAA==.',
Ga='Garidrael:BAAANQABCgMIAwAAAA==.',
Ge='Gebran:BAAANQAECgIJBwAAAA==.Gellywoo:BAAANQAECgEIAgAAAA==.Gemmarolizzy:BAAANQAECgEIAQAAAA==.',
Go='Golaoth:BAAANQAECgIJAwAAAA==.Gooftroupe:BAAANQAECgUJCwAAAA==.',
Gr='Grandmaster:BAAANQAECgYIDAABNQAECgEIAQADAAAAAA==.Greymoon:BAAANQADCggJFwAAAA==.Grimtotems:BAAANQADCgMIAwAAAA==.',
Gu='Guayuelf:BAAANQAECgQICQAAAA==.',
Ha='Haezi:BAAANQAECgMIAwABNQAECgUIDAADAAAAAA==.Haki:BAAANQABCgIIAgAAAA==.Hammerbully:BAAANQADCgEIAQAAAA==.Happyendings:BAAANQAECgMIAwAAAA==.',
He='Helbafx:BAAANQADCggIHQAAAA==.',
Hi='Hino:BAAANQAECgQJBAAAAA==.',
Ho='Homewrecker:BAAANQADCggJFQAAAA==.Horuid:BAAANQADCgEIAQAAAA==.',
Ic='Icemàn:BAAANQADCgMJAwAAAA==.',
Id='Idrazil:BAAANQAECgYICgAAAA==.',
If='Ifearnobeer:BAAANQAECgMIBAAAAA==.',
In='Infectz:BAAANQAECggJAgAAAA==.Infoxicated:BAAANQADCgQIBAAAAA==.',
It='Itburnsalot:BAAANQADCgYIBgAAAA==.',
Ja='Jaiantobea:BAABNQAECoEoAAIMAAkKoR8lCgA+AwAMAAkKoR8lCgA+AwAAAA==.Jakik:BAAANQADCgUIBQAAAA==.Jawn:BAAANQAECgQICwAAAA==.',
Je='Jessuss:BAAANQAECgEJAQAAAA==.',
Jh='Jha:BAAANQAECgUJBwAAAA==.',
Ju='Jude:BAAANQAECgQICQAAAA==.Junipermoon:BAAANQADCgYICgAAAA==.',
Ka='Kabub:BAAANQAECgUJBwAAAA==.Kalahandra:BAABNQAECoEWAAIHAAcKLhH3GwC9AQAHAAcKLhH3GwC9AQAAAA==.Kalebeesd:BAAANQADCgUIBwAAAA==.Katablight:BAAANQAECggICwAAAA==.Katotan:BAAANQAECgYIDwAAAA==.',
Ke='Kealestra:BAAANQAECgIJAwAAAA==.Keyboärd:BAAANQAECgMIAwAAAA==.',
Ki='Kippo:BAEANQADCgcIBwABNQAECgcICAADAAAAAA==.Kittylover:BAAANQADCgMIBgAAAA==.',
Ko='Kombat:BAAANQADCgYJCgAAAA==.Korllan:BAAANQADCgIIAgAAAA==.Kossnen:BAAANQAECgEIAQAAAA==.',
Kr='Krestisnack:BAAANQAECgIJAgAAAA==.',
Ku='Kuda:BAAANQAECgIJAwAAAA==.Kullkil:BAAANQADCggIEQAAAA==.',
Kw='Kwanu:BAAANQAECgMIBgAAAA==.',
['Kñ']='Kño:BAAANQADCgMIAwABNQADCggIEgADAAAAAA==.',
['Kó']='Kóñä:BAAANQADCggIEgAAAA==.',
La='Larke:BAAANQADCgYIBgAAAA==.Lasa:BAAANQAECgEIAQAAAA==.Lasloo:BAAANQAECgUIDgAAAA==.Laylani:BAAANQAECgYIEQAAAA==.',
Le='Leynreite:BAAANQAECgEIAQAAAA==.',
Li='Lisan:BAAANQAECgUIBwAAAA==.Littledicey:BAAANQAECgYJDgAAAA==.',
Lu='Luciä:BAAANQAECgIJAwAAAA==.Lucymoon:BAAANQAECgYIBgAAAA==.Luvflap:BAAANQADCgMIAwAAAA==.',
Ly='Lyñx:BAAANQADCgQIBgAAAA==.',
Ma='Madness:BAAANQAECgQIBAAAAA==.Maerion:BAAANQAECgQJBQAAAA==.Magdeth:BAAANQABCgYJCgAAAA==.Marabelle:BAAANQAECgMIBAAAAA==.Marasteil:BAAANQADCgIIAgAAAA==.Marixia:BAAANQAECgUJBQAAAA==.Masilitu:BAAANQADCgYIDwAAAA==.Massack:BAAANQAECgQJCgAAAA==.Mawgwa:BAAANQAECgMIAwAAAA==.',
Me='Meeow:BAAANQADCgEIAQABNQAECgUIDAADAAAAAA==.Mero:BAAANQAECgcJEgAAAA==.',
Mi='Midgetmàniàc:BAAANQADCggICAAAAA==.',
Mo='Mosimo:BAAANQABCgIIAgAAAA==.Moushuhan:BAAANQAECgYIEQAAAA==.',
My='Mystrall:BAAANQAECgQIBAAAAA==.',
Na='Naanaa:BAAANQADCggJDwAAAA==.Nadorian:BAAANQABCgIIAgAAAA==.',
Ne='Neb:BAAANQAECgEIAQAAAA==.Netherrogue:BAABNQAECoEXAAMNAAkK+CC4AwCkAgANAAcKkyK4AwCkAgAOAAIKWhsjSwCgAAAAAA==.',
No='Noesis:BAAANQADCgQJBAAAAA==.',
Nu='Nuke:BAAANQAECgIIAgABNQAECgUJCgADAAAAAA==.',
Ny='Nytehuntrix:BAAANQADCggJDgABNQAECgkJHQAPAB0cAA==.Nytemayer:BAABNQAECoEdAAMPAAkKHRyAJACUAgAPAAgKfxyAJACUAgAQAAMKtRMTNgDGAAAAAA==.',
Ob='Obmakare:BAAANQADCggJFwAAAA==.Obonhigh:BAAANQADCgEIAQAAAA==.Oboñ:BAAANQADCggJFQAAAA==.Obsfuyung:BAAANQAECgIJBQAAAA==.',
Oo='Oopsiez:BAAANQAECgEJAgAAAA==.',
Op='Opiishift:BAAANQAECgYIDQAAAA==.Opiishots:BAAANQADCgQIBAAAAA==.',
Pa='Paley:BAAANQADCggIEgAAAA==.',
Pd='Pdgrimm:BAAANQADCgQIBAAAAA==.',
Pe='Performance:BAABNQAECoEcAAIRAAgKaxbhBQAwAgARAAgKaxbhBQAwAgAAAA==.Peterturbo:BAAANQAECgQICAABNQABCgIIAgADAAAAAA==.',
Pi='Pinkky:BAAANQADCgcIBwAAAA==.',
Po='Pocketfox:BAAANQADCgYIBgAAAA==.Poîsonivy:BAAANQAECgIJAwAAAA==.',
Ps='Psyrine:BAAANQADCgYIFQAAAA==.',
Qu='Qu:BAABNQAECoEcAAISAAgKOhN7WQAIAgASAAgKOhN7WQAIAgAAAA==.',
Ra='Rattlesnake:BAAANQADCggJEwAAAA==.Raymonnd:BAAANQADCgYIBgAAAA==.',
Re='Renägäde:BAAANQAECgMIBAAAAA==.Retiredfurry:BAAANQAECgQJDAAAAA==.',
Ri='Ricodadawg:BAABNQAECoEfAAIIAAgKciKrKAAYAwAIAAgKciKrKAAYAwAAAA==.',
Ro='Roshak:BAAANQADCgYICgAAAA==.Rotspawn:BAAANQAECggJCAAAAA==.',
Ru='Runningbearr:BAAANQADCggIEgAAAA==.Runningshama:BAAANQAECgYIDAAAAA==.Rurahk:BAAANQAECgYIDwAAAA==.',
['Rõ']='Rõbb:BAAANQAECgEIAQAAAA==.',
Sa='Sabaak:BAAANQADCggJEAAAAA==.Sabel:BAAANQADCggIDgAAAA==.Saintsnyder:BAABNQAECoEWAAQEAAkKkgxtJQAhAQAEAAUKdxRtJQAhAQALAAgKzAU3rgALAQATAAEKGgGS5wAPAAAAAA==.Saithis:BAAANQAECgEIAQAAAA==.Sanorasong:BAAANQAECgIJAwAAAA==.Saphirra:BAAANQADCggJEQAAAA==.Sarylin:BAAANQAECgMIAwAAAA==.Satansshadow:BAAANQADCgEIAQAAAA==.Sathpriest:BAAANQAECgcJEgAAAA==.Sathrel:BAAANQADCgMIAwAAAA==.',
Sc='Schio:BAAANQADCggJFwAAAA==.',
Se='Severussnape:BAAANQAECgQJCgAAAA==.',
Sh='Shamrorag:BAAANQADCgQICAAAAA==.She:BAAANQAECgcIEAAAAA==.Shehealz:BAAANQADCggICQAAAA==.Shekxxy:BAAANQADCgYJBgAAAA==.Shortstack:BAAANQAECgYIDAAAAA==.',
Si='Sinensis:BAAANQAECgEIAQAAAA==.',
Sk='Skadoosh:BAAANQADCggIDQABNQAECgkJJgAJAE8cAA==.Skarletflame:BAAANQADCgMIAwAAAA==.Skarletrose:BAAANQAECgEIAQAAAA==.',
Sl='Slaycie:BAAANQADCggJFgAAAA==.',
Sn='Sneek:BAAANQADCggICAAAAA==.Snugglebus:BAAANQAECgIIAgAAAA==.',
So='Solaara:BAAANQADCggICAAAAA==.',
Sp='Spaghett:BAAANQAECgUIDAAAAA==.',
St='Stanger:BAAANQADCgcJDAABNQAECgUIDAADAAAAAA==.Starlight:BAAANQAECgQJBQABNQAECgYIEAADAAAAAA==.',
Sy='Syrden:BAABNQAECoEYAAIHAAgKlAnSHwCRAQAHAAgKlAnSHwCRAQAAAA==.Syren:BAAANQADCgEIAQAAAA==.',
Ta='Tael:BAAANQAECgUJDQAAAA==.Tangylizard:BAAANQAECgQJBwAAAA==.Tawainai:BAAANQAECgUIEAAAAA==.',
Te='Tessla:BAAANQAECgYJEQAAAA==.Tetragram:BAABNQAECoEZAAICAAgKzxwCDgCdAgACAAgKzxwCDgCdAgAAAA==.',
Th='Thelarï:BAAANQAECgQJCgAAAA==.Thors:BAAANQADCggIDQAAAA==.Thundertoes:BAAANQAECgQJCgAAAA==.',
Ti='Timmy:BAAANQADCgIIAgAAAA==.Tiquandeisha:BAAANQADCggJFwAAAA==.',
To='Tonik:BAAANQAECgQJBwAAAA==.Torgoth:BAAANQAECgIJAwAAAA==.Toshido:BAAANQAECgEIAQAAAA==.Toy:BAAANQADCggICAAAAA==.',
Tr='Trevize:BAAANQADCgcIEwAAAA==.',
Tw='Twilightsoul:BAAANQAECggIAQAAAA==.',
Ul='Ultane:BAAANQAECgEJAQAAAA==.',
Un='Unholypally:BAAANQADCgMIAwAAAA==.',
Va='Valashar:BAAANQADCgcIDQAAAA==.Valiantaine:BAABNQAECoEcAAMLAAgKYBuXNQB/AgALAAgKYBuXNQB/AgATAAUKhAOFkwDgAAAAAA==.Valiantaint:BAAANQAECgUJCAABNQAECggJHAALAGAbAA==.Valiantroar:BAAANQAECgYIBgABNQAECggJHAALAGAbAA==.Vashon:BAAANQADCgQJBgAAAA==.',
Ve='Velherun:BAAANQAECgQJCQAAAA==.Vendel:BAABNQAECoEcAAIUAAgKfCMVDwA8AwAUAAgKfCMVDwA8AwAAAA==.Vexxaa:BAAANQAECgIJAwAAAA==.',
Vi='Virajr:BAAANQADCgcIDgAAAA==.Vissiction:BAAANQAECgQJCAAAAA==.Vistine:BAAANQAECgQIBAABNQAECgYJEQADAAAAAA==.Vitez:BAAANQAECgUJBwAAAA==.',
Wa='Waterslide:BAAANQADCgMJAwAAAA==.',
We='Wendy:BAAANQAECgYIDwAAAA==.',
Wh='Whitesox:BAAANQADCgQJBAAAAA==.',
Wi='Win:BAAANQAECgUJCgAAAA==.',
Xa='Xanadu:BAAANQAECgUIDwAAAA==.',
Xb='Xbear:BAAANQAECgIJAwABNQAECgkJJgAVANkbAA==.',
Xd='Xdynasty:BAABNQAECoEmAAMVAAkK2RtOCADQAgAVAAkKiRlOCADQAgAOAAQK5Re4NQAtAQAAAA==.',
Xe='Xendier:BAAANQADCgIIAgAAAA==.',
Xi='Xióngchäo:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.',
Xo='Xo:BAAANQADCggICAABNQAECgUJCgADAAAAAA==.',
Za='Zabazz:BAAANQAECgUJDgAAAA==.Zabenir:BAAANQAECgIJAwAAAA==.Zaraina:BAAANQAECgIIAwABNQAECgkJJgAJAE8cAA==.',
Ze='Zerototem:BAABNQAECoEZAAIMAAgK2RDGSwC6AQAMAAgK2RDGSwC6AQAAAA==.',
Zo='Zorusii:BAAANQADCgcIDQABNQAECgkJJgAJAE8cAA==.',
['Çu']='Çuddleybunny:BAAANQADCgUIBQAAAA==.',
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
