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

local lookup = {'Paladin-Retribution','Mage-Arcane','Unknown-Unknown','Monk-Windwalker','Warrior-Fury','Warlock-Demonology','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','DemonHunter-Havoc','Warrior-Arms','Paladin-Protection','Warlock-Destruction','Warrior-Protection','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Hunter-BeastMastery','Monk-Brewmaster','Druid-Balance','Rogue-Outlaw','Warlock-Affliction',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acupuncher:BAAANQAECgIIAgAAAA==.',
Ad='Adamsandler:BAAANQADCggICAAAAA==.Adiwolf:BAAANQAECgIIBAAAAA==.',
Al='Alcha:BAAANQAECgMICAAAAA==.Alenndar:BAAANQADCgEIAQAAAA==.Alexdaddario:BAAANQAECgQICAAAAA==.Algaefungi:BAAANQAECgEJBAAAAA==.Althena:BAAANQADCgQIBAABNQAECggIGgABAKwcAA==.Alystana:BAAANQADCgUIBwAAAA==.',
An='Anastera:BAAANQADCgYIBwAAAA==.Animeniac:BAAANQAECgMJBQAAAA==.Anticlimax:BAAANQAECgYJCgAAAA==.Antilaw:BAAANQAECgEJAQAAAA==.Antisocial:BAAANQAECgEJAQAAAA==.',
Ao='Aoibhneas:BAAANQADCgcIBwAAAA==.',
Ap='Apprentice:BAABNQAECoEaAAICAAkKxiMyFABoAwACAAkKxiMyFABoAwAAAA==.',
Ar='Artrael:BAAANQADCggJCAAAAA==.',
At='Atorim:BAAANQADCgIIAgABNQADCgYIFQADAAAAAA==.',
Av='Avienndha:BAAANQAECgMJBQAAAA==.Avriel:BAAANQAECgQIBQABNQAECggIGgABAKwcAA==.',
Ba='Barbatos:BAAANQAECgEJAQAAAA==.',
Be='Beardeddrunk:BAAANQADCgUJBQAAAA==.Beornwildlaw:BAAANQABCgcIEAAAAA==.',
Bo='Bobbytofva:BAAANQAECgEIAQAAAA==.Boochaka:BAAANQAECgYJCgAAAA==.Bouquet:BAAANQAECgIIAgAAAA==.',
Br='Brewdog:BAAANQAECgQJCgAAAA==.Brickfists:BAAANQADCgQIBAAAAA==.Brotherfuzz:BAAANQAECgIIAwAAAA==.',
Bu='Busterposer:BAAANQAECgIIAgAAAA==.',
Ca='Caelvaris:BAAANQADCgEJAQAAAA==.Calabooca:BAAANQADCgUICAAAAA==.Canadaclown:BAAANQADCgIJAgAAAA==.Candor:BAAANQADCgUIBQAAAA==.',
Ch='Cheesefries:BAAANQAECgMJBQAAAA==.',
Cl='Clapton:BAAANQAECgQJBAAAAA==.Claptone:BAAANQAECgUJBAAAAA==.',
Co='Corpuscle:BAAANQAECgYICgAAAA==.',
Cr='Critcomander:BAAANQAECgYIDQAAAA==.Critties:BAAANQADCgMIAwAAAA==.Crueldin:BAAANQAECgUJCQAAAA==.',
Da='Dalsen:BAAANQAECgUJDQAAAA==.Dalvulpe:BAAANQADCgEIAQABNQAECgUJDQADAAAAAA==.Dankchop:BAAANQAECgUJBgAAAA==.Darkbishop:BAAANQABCgYICwAAAA==.Darklink:BAAANQADCgUJCAAAAA==.Dawnlighted:BAAANQADCgMIAwAAAA==.',
De='Deadlyshiet:BAAANQAECgIJAgABNQAFFAYIEwAEABsWAA==.Denrin:BAAANQADCggIDQAAAA==.Deskpop:BAAANQADCgQIBAAAAA==.',
Di='Diabolikal:BAAANQABCgQIBwABNQABCgUIBwADAAAAAA==.Dill:BAABNQAECoEdAAIFAAgKXyNFAQBKAwAFAAgKXyNFAQBKAwAAAA==.Divinesmite:BAAANQABCgcICQAAAA==.',
Dm='Dmachine:BAAANQAECgcIEAABNQAFFAQJCQAGADkjAA==.',
Do='Dondeezy:BAAANQABCgIJAwAAAA==.',
Dr='Drdru:BAAANQAECgUJDAABNQADCgUIBQADAAAAAA==.Dreadshade:BAAANQADCgcIBwAAAA==.Dropfort:BAAANQAECgYIBgAAAA==.Drscruffles:BAAANQADCgcIBwAAAA==.',
Du='Durkidurk:BAAANQADCgMIAwAAAA==.',
Dy='Dyabolykal:BAAANQABCgUIBwAAAA==.',
Ea='Easily:BAAANQAECgYIDgAAAA==.',
El='Ellyanthia:BAAANQAECgMJAwAAAA==.',
Em='Emachine:BAAANQADCgcIBwABNQAFFAQJCQAGADkjAA==.',
Ex='Exio:BAAANQAECgQJCgAAAA==.',
Fa='Fastasheet:BAACNQAFFIETAAIEAAYKGxbdAQD9AQAEAAYKGxbdAQD9AQA1AAQKgSUAAgQACQpqJbYBALgDAAQACQpqJbYBALgDAAAA.',
Fi='Fill:BAABNQAECoEZAAIHAAkKnyRPAQCcAwAHAAkKnyRPAQCcAwAAAA==.',
Fl='Flehtwo:BAABNQAECoEhAAMIAAkK2RsjHgC9AgAIAAkK2RsjHgC9AgAJAAgKQwpYUACnAQAAAA==.Flyinbanana:BAAANQADCgIIAgABNQAECgUICQADAAAAAA==.',
Fr='Fraglen:BAAANQADCgUIBQABNQAECgcICgADAAAAAA==.Frags:BAAANQAECgcICgAAAA==.Fránknárf:BAAANQADCgIJAgAAAA==.',
Ge='Genjyosanzo:BAAANQAECgMJBAAAAA==.',
Gh='Ghorn:BAAANQADCgcICgAAAA==.Ghostkrim:BAAANQADCgUIBQAAAA==.',
Gi='Gilljoww:BAABNQAECoEaAAIKAAgKix9DFQC0AgAKAAgKix9DFQC0AgAAAA==.Gireigtulb:BAAANQADCgYIBgAAAA==.',
Gn='Gnzz:BAAANQAECgYIDQAAAA==.',
Go='Gocirr:BAAANQAECgEJAQAAAA==.',
Gr='Grito:BAAANQADCgYICgAAAA==.',
Ha='Haehn:BAAANQADCgMIAwAAAA==.Halstorm:BAAANQAECgQJBQAAAA==.Harrysax:BAAANQABCgYIBgAAAA==.',
He='Hexxytime:BAAANQADCgQIBAAAAA==.',
Hi='Hilazy:BAAANQAECgIJAwAAAA==.',
Hm='Hm:BAAANQADCggJCwAAAA==.',
Ho='Holyfed:BAAANQADCgQIBAAAAA==.Holyphok:BAAANQAECgEJAQAAAA==.Hotdog:BAAANQAECgUJAgAAAA==.',
Ic='Icestormy:BAAANQADCgUJCgAAAA==.',
Ih='Ihavenofutur:BAAANQADCgcIDQAAAA==.',
Il='Iliil:BAAANQAECgcJDwAAAA==.Illbiteyou:BAAANQADCgQIBAAAAA==.Illidantwo:BAACNQAFFIEHAAILAAQKeBDQBQA+AQALAAQKeBDQBQA+AQA1AAQKgSAAAgsACQrrI0kHAE4DAAsACQrrI0kHAE4DAAAA.',
Im='Imprints:BAAANQAECgQJBQAAAA==.',
In='Inuk:BAAANQAECgYJDQAAAA==.',
Ir='Ironshaman:BAAANQAECgYIDQAAAA==.',
It='Italianapee:BAAANQADCggICAABNQAECgYJDQADAAAAAA==.',
Ja='Jabu:BAAANQADCgQIAwABNQADCgYIBgADAAAAAA==.Jada:BAAANQAECgQJBAAAAA==.Jaghatai:BAAANQADCgIIAgAAAA==.',
Je='Jenstonedart:BAAANQAECgQIDQAAAA==.Jeryeth:BAABNQAECoEZAAIMAAgK0h/IKwC9AgAMAAgK0h/IKwC9AgAAAA==.Jeryzard:BAAANQADCgYIDAAAAA==.',
Ji='Jiannybon:BAAANQADCgQICwAAAA==.',
Ju='Judidench:BAAANQAECgcIBwAAAA==.Juicewillis:BAAANQADCgIIAgAAAA==.',
Ka='Kain:BAECNQAFFIEKAAINAAUKOx5JAQDgAQANAAUKOx5JAQDgAQA1AAQKgR4AAw0ACQp9JXcBALMDAA0ACQp9JXcBALMDAAEAAQo4CmYnATAAAAAA.Kane:BAAANQAECgUJCgAAAA==.Karmasuture:BAAANQADCgYJBgABNQAECgMIAwADAAAAAA==.Kaïn:BAAANQAECgEIAQABNQAECggIGgABAKwcAA==.',
Ke='Kelsí:BAAANQAECgMJBQAAAA==.',
Ki='Kikisan:BAAANQABCgEIAgAAAA==.Kiwí:BAAANQAECgUIDgAAAA==.',
Kr='Krasavice:BAAANQAECgYJEQAAAA==.Krenik:BAAANQADCggIHwAAAA==.Krimsondeath:BAAANQADCgQIBAAAAA==.Krimtohell:BAAANQADCggIBQAAAA==.Krisp:BAAANQAECgEIAQABNQADCgQIBAADAAAAAA==.',
Ku='Kurquaan:BAAANQADCggICAAAAA==.',
La='Lauranthalas:BAAANQAECgIIAwAAAA==.Lavenderhaze:BAAANQADCgEIAQAAAA==.',
Le='Leathal:BAAANQAECgUICgAAAA==.Lemurshoes:BAAANQAECgIIAwAAAA==.Lemursneaker:BAAANQAECgUJCQAAAA==.Letsgomen:BAAANQADCgEJAQAAAA==.',
Li='Lightshock:BAAANQADCggIGgAAAA==.',
Ll='Llaagg:BAAANQAECgIIAgAAAA==.',
Lo='Lokust:BAAANQAECgQIBQAAAA==.',
Lu='Lucentdawn:BAAANQAECgQIBQAAAA==.Luckyshrine:BAAANQABCggICwAAAA==.Ludachris:BAAANQAECgEIAQAAAA==.',
Ly='Lycanius:BAAANQAECgYIEAAAAA==.Lynqii:BAAANQAFFAQIBAAAAA==.',
Ma='Malëk:BAABNQAECoEaAAIBAAgKrBylMACVAgABAAgKrBylMACVAgAAAA==.Maximus:BAAANQADCgUIBQAAAA==.',
Me='Medallis:BAAANQABCgMIBgAAAA==.Mellowlizard:BAACNQAFFIEJAAMGAAQKOSOYCAAzAQAGAAMKhCKYCAAzAQAOAAEKViWdCwBxAAA1AAQKgSAAAwYACQrqIlgSAPwCAAYACAovI1gSAPwCAA4AAwr2HvQvAOIAAAAA.Metuss:BAAANQAECgUJCAAAAA==.',
Mi='Miguel:BAAANQAECgUJDgAAAA==.Mira:BAAANQAECgYJCgAAAA==.',
Mk='Mkicon:BAAANQAECgQIBQAAAA==.Mkultra:BAAANQAECgYIBwAAAA==.',
Mo='Mogmoog:BAAANQAECgIIBAAAAA==.Moonangel:BAAANQAECgMJBQAAAA==.Morbodan:BAAANQAECgYJEAAAAA==.Mornangus:BAAANQABCgIIAwAAAA==.Motone:BAAANQAECgMJBAAAAA==.',
Mu='Multanni:BAAANQAECgYICQAAAA==.',
My='Myonecrosis:BAAANQAECgMJBQAAAA==.',
Na='Nakrog:BAABNQAECoEXAAIPAAcK1hj2CgABAgAPAAcK1hj2CgABAgAAAA==.Napster:BAAANQADCgcIDAAAAA==.Nasa:BAACNQAFFIEHAAIEAAQKkAy8BAAqAQAEAAQKkAy8BAAqAQA1AAQKgSEAAgQACQoUHikKAOQCAAQACQoUHikKAOQCAAAA.',
Ne='Nellarixi:BAABNQAECoEaAAIQAAgKkxwZDwCuAgAQAAgKkxwZDwCuAgAAAA==.Nethus:BAAANQADCgcJCQAAAA==.',
Ni='Niivalyr:BAAANQABCgIJAQAAAA==.Nimbus:BAAANQADCggIDgABNQAFFAUICAAIALYTAA==.',
No='Nodens:BAAANQADCgcIEwAAAA==.Nomaa:BAAANQAECgMJBQAAAA==.Nomäd:BAAANQADCggIDAAAAA==.Nosneb:BAAANQADCgEIAQABNQADCggIDQADAAAAAA==.',
Ny='Nytedevil:BAAANQAECgQJBwAAAA==.',
['Nì']='Nìtsua:BAAANQADCggIDQAAAA==.',
Ob='Obilivion:BAAANQADCgYICgAAAA==.',
Og='Ogmount:BAAANQAECgMIAwAAAA==.',
Or='Orflame:BAABNQAECoEaAAMRAAgKeQelHACHAQARAAgKeQelHACHAQASAAEKtQEjGgAoAAAAAA==.',
Ph='Phrash:BAAANQAECgcICgABNQAECgkJGQAHAJ8kAA==.',
Pi='Pigbearmans:BAAANQADCgYIBgAAAA==.',
Pl='Plex:BAAANQADCgQIBAABNQAECgkJHQATAGEgAA==.',
Po='Pooldan:BAAANQAECgMJAgAAAA==.',
Pr='Praystatioñ:BAAANQAECgYIDwAAAA==.Premiumgank:BAAANQAECgIJAgAAAA==.Prtanks:BAAANQAECgMIAwAAAA==.',
Pu='Purerform:BAAANQADCgcIBwAAAA==.',
Qu='Quelidra:BAAANQADCgUIBQAAAA==.Quepaspete:BAAANQADCgYIBwAAAA==.',
Ra='Raa:BAABNQAECoEeAAIUAAgKmh02FwDvAgAUAAgKmh02FwDvAgAAAA==.Racker:BAAANQAECgIJAgAAAA==.Ragou:BAAANQADCgQIBAAAAA==.',
Re='Rengots:BAAANQADCgYIDAAAAA==.Rephtide:BAAANQAECgQJBQAAAA==.Responsible:BAAANQAECgYIDAAAAA==.',
Rh='Rhaez:BAAANQADCggIGAAAAA==.Rhetoricdork:BAAANQAECgQIBAABNQAFFAYJDAACAHEcAA==.',
Ro='Rogmash:BAAANQAECgUJCwAAAA==.Rokkoz:BAAANQAECgYICwAAAA==.Romer:BAABNQAECoEgAAIVAAkKSwiMDgCaAQAVAAkKSwiMDgCaAQAAAA==.Rookiestar:BAAANQADCggJGgAAAA==.',
Sa='Sabb:BAAANQADCgYIEAAAAA==.Saphroniå:BAAANQADCgcIGQAAAA==.Sass:BAABNQAECoEZAAIWAAgKrhi7IwBPAgAWAAgKrhi7IwBPAgAAAA==.Sazed:BAAANQADCgEIAQAAAA==.',
Sc='Schend:BAAANQADCgYICwAAAA==.',
Se='Sed:BAAANQAECgIIAwAAAA==.Serrana:BAAANQADCgUIBQAAAA==.',
Sf='Sfinktor:BAAANQADCgMIAgAAAA==.',
Sh='Shadowmortis:BAAANQAECgQJBQAAAA==.Shirokhan:BAAANQAECggJCgAAAA==.',
Si='Sidewinderx:BAAANQADCgEIAQAAAA==.Sinlock:BAABNQAECoEcAAMGAAgKfh1vLgBmAgAGAAcKnB1vLgBmAgAOAAQKMxFZKgAEAQAAAA==.',
Sk='Skrot:BAAANQADCgYIBgAAAA==.',
Sn='Snagglespark:BAAANQAECgcIEAAAAA==.Sneakylink:BAAANQADCgYIBgAAAA==.Snowbunni:BAAANQADCgYIBwAAAA==.',
So='Soladrian:BAAANQAECgQIBAAAAA==.Solanthion:BAEANQADCgcIBwABNQAECgIIAgADAAAAAA==.',
Sp='Spankyee:BAAANQADCgQIBAAAAA==.',
St='Starz:BAAANQADCgYJBAAAAA==.',
Su='Sunchipzz:BAAANQADCgQIBAAAAA==.Sundayschool:BAAANQAECgcJEgAAAA==.',
Sy='Syyia:BAAANQADCgIIAgAAAA==.',
['Sé']='Séraph:BAAANQAECgIIAwAAAA==.',
['Só']='Sóozabimaru:BAAANQAECgQJBQAAAA==.',
Ta='Tahano:BAAANQABCgIIAgAAAA==.Talljeff:BAAANQAECggICgAAAA==.Tankarmor:BAAANQAECgQIBQAAAA==.Taylorswif:BAABNQAECoEaAAICAAkKzBn7PADVAgACAAkKzBn7PADVAgAAAA==.',
Tc='Tcharta:BAAANQAECgUICQAAAA==.',
Th='Thefamousone:BAAANQADCgYICAAAAA==.Thermotide:BAAANQAECgUJCAAAAA==.Thoror:BAAANQADCgYICwAAAA==.Thunderbolt:BAAANQADCgcJBwABNQAECgQIBAADAAAAAA==.Thundernütz:BAAANQADCgIIAgAAAA==.Thymós:BAAANQAECgMIBgAAAA==.',
Ti='Tiffina:BAAANQADCgYICQAAAA==.Tiffzen:BAAANQAECgUICgAAAA==.Timeskip:BAAANQADCggIBgAAAA==.Tinyfaith:BAAANQADCgYICwAAAA==.Titum:BAAANQAFFAEIAQABNQAECgkJHQACAHUVAA==.',
To='Tongpooh:BAABNQAECoEYAAIEAAgKPxNNFQAlAgAEAAgKPxNNFQAlAgABNQADCgYIBgADAAAAAA==.',
Tr='Treeberk:BAAANQAECgIIAgAAAA==.',
Tu='Tuba:BAAANQAECggIAQAAAA==.Tuckerherout:BAAANQAECgYIEAAAAA==.Tundro:BAAANQADCgUIBgAAAA==.',
Tw='Twix:BAAANQAECgIIAgABNQAECgQJCgADAAAAAA==.',
['Tî']='Tîtån:BAAANQAECgQIBQAAAA==.',
Uh='Uh:BAAANQAECgYICgABNQAECgkJGQAHAJ8kAA==.',
Un='Undeadlock:BAAANQAECgEIAQAAAA==.',
Va='Vale:BAAANQADCgEIAQAAAA==.',
Vg='Vgmking:BAABNQAECoEdAAIKAAgKHBAKOAC3AQAKAAgKHBAKOAC3AQAAAA==.',
Vi='Vindorei:BAAANQADCgUIDgAAAA==.',
Vo='Vokzhen:BAAANQAECgUJCwAAAA==.Volescu:BAAANQAECgMJAwAAAA==.',
Wa='Walkerboah:BAAANQAECgYJBgAAAA==.Warmachinne:BAAANQADCgYIBgAAAA==.',
We='Weel:BAAANQAECgYJEQAAAA==.',
Wo='Wolfspider:BAAANQAECgIIAwAAAA==.',
Wy='Wyland:BAAANQAECgMIBQAAAA==.Wylander:BAAANQAECgQJBAAAAA==.Wylandvoker:BAAANQADCgIIAgAAAA==.',
Xa='Xanun:BAAANQADCgMIAwAAAA==.',
Xe='Xeri:BAAANQAECgQJBAABNQAFFAQJBwAXACUdAA==.Xeromus:BAAANQAECgMJAwAAAA==.Xetsus:BAAANQADCgUJBQAAAA==.',
Ya='Yang:BAAANQABCgEIAQAAAA==.',
Yo='Yoink:BAAANQADCgUIBQAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Yv='Yvelmaya:BAAANQAECgMJBQAAAA==.',
Za='Zaboomaprune:BAAANQAECgUIBwAAAA==.Zarika:BAACNQAFFIEHAAIXAAQKJR17AACTAQAXAAQKJR17AACTAQA1AAQKgSQAAhcACQptJh0AAPUDABcACQptJh0AAPUDAAAA.Zarì:BAAANQAECgUIBwABNQAFFAQJBwAXACUdAA==.',
Ze='Zeknull:BAAANQAECgcIEwAAAA==.Zenio:BAAANQADCgIIAgAAAA==.Zennah:BAAANQADCgYJBgAAAA==.Zephy:BAAANQADCgcJCQAAAA==.',
Zr='Zrgl:BAAANQADCggICAAAAA==.',
['Zä']='Zäo:BAABNQAECoEhAAQYAAkK1iKXAABnAwAYAAkKYyCXAABnAwAGAAUKQR7hXQCwAQAOAAMKKRuBLgDqAAAAAA==.',
['Ïk']='Ïkea:BAAANQAECgQIBwAAAA==.',
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
